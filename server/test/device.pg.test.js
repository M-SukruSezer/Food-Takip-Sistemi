// Hesap-telefon eslestirmesi: ilk telefona baglanma, baska telefonda bloke,
// yonetici bildirimi, blokeyi kaldirma ve cihaz sifirlama.
// TEST_DATABASE_URL yoksa atlanir.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');

const URL = process.env.TEST_DATABASE_URL;
const skip = !URL && 'TEST_DATABASE_URL tanımlı değil';
let db, server, base, ids;

before(async () => {
  if (skip) return;
  process.env.DATABASE_URL = URL;
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';
  require('express-async-errors');
  db = require('../src/db');
  const auth = require('../src/auth');
  await db.initialize();
  await db.pool.query('TRUNCATE notifications, activity_logs, users, stores RESTART IDENTITY CASCADE');
  const a = await db.queryOne("INSERT INTO stores (name) VALUES ('A') RETURNING id");
  const hash = auth.hashPassword('secret1');
  const user = async (n, role, s) => Number((await db.queryOne(`INSERT INTO users
    (store_id, username, password_hash, full_name, role) VALUES (?,?,?,?,?) RETURNING id`,
  s, n, hash, n, role)).id);
  ids = {
    admin: await user('admin', 'super_admin', null),
    mudur: await user('mudur', 'store_manager', a.id),
    barista: await user('barista', 'barista', a.id),
    barista2: await user('barista2', 'barista', a.id),
  };
  const express = require('express');
  const app = express();
  app.use(express.json());
  app.use('/api', require('../src/routes'));
  app.use((err, req, res, next) => res.status(500).json({ error: err.message }));
  server = app.listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}/api`;
});
after(async () => {
  if (skip) return;
  await new Promise((r) => server.close(r));
  await db.pool.end();
});

async function call(method, path, { token, device, body } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  if (device) { headers['x-device-id'] = device; headers['x-device-name'] = `Telefon ${device}`; }
  const res = await fetch(base + path, {
    method, headers, body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}
const login = (username, device, password = 'secret1') =>
  call('POST', '/auth/login', { device, body: { username, password } });

let mudurToken;

test('ilk telefona eslesir; ayni telefonda acilir', { skip }, async () => {
  const r = await login('barista', 'A');
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const row = await db.queryOne('SELECT device_id, device_name FROM users WHERE id = ?', ids.barista);
  assert.equal(row.device_id, 'A');
  assert.equal(row.device_name, 'Telefon A');
  assert.equal((await call('GET', '/auth/me', { token: r.body.token, device: 'A' })).status, 200);
  assert.equal((await login('barista', 'A')).status, 200);
  mudurToken = (await login('mudur', 'M')).body.token;
});

test('yanlis sifre bloke ettirmez', { skip }, async () => {
  assert.equal((await login('barista', 'X', 'yanlis')).status, 401);
  const row = await db.queryOne('SELECT device_blocked FROM users WHERE id = ?', ids.barista);
  assert.equal(Number(row.device_blocked), 0);
});

test('baska telefonda acilinca bloke olur, yonetici bildirim alir', { skip }, async () => {
  const eski = (await login('barista', 'A')).body.token;
  const r = await login('barista', 'B');
  assert.equal(r.status, 403);
  assert.equal(r.body.code, 'DEVICE_BLOCKED');
  // Bloke her yerde gecerli: kayitli telefonda da, acik oturumda da.
  assert.equal((await login('barista', 'A')).status, 403);
  const me = await call('GET', '/auth/me', { token: eski, device: 'A' });
  assert.equal(me.status, 403);
  assert.equal(me.body.code, 'DEVICE_BLOCKED');

  const bildirim = await db.queryAll(
    "SELECT user_id, body FROM notifications WHERE kind = 'DEVICE_BLOCKED'");
  const alicilar = bildirim.map((b) => Number(b.user_id)).sort();
  assert.deepEqual(alicilar, [ids.admin, ids.mudur].sort());
  assert.match(bildirim[0].body, /Telefon B/);
  const log = await db.queryOne("SELECT details FROM activity_logs WHERE action = 'CIHAZ_BLOKE'");
  assert.ok(log);

  const list = await call('GET', '/users', { token: mudurToken, device: 'M' });
  const b = list.body.find((u) => u.id === ids.barista || Number(u.id) === ids.barista);
  assert.equal(b.device_blocked, true);
  assert.equal(b.device_bound, true);
  assert.equal(b.blocked_device_name, 'Telefon B');
});

test('personel blokeyi kaldiramaz; yonetici kaldirir, telefon ayni kalir', { skip }, async () => {
  const b2 = (await login('barista2', 'C')).body.token;
  assert.equal((await call('POST', `/users/${ids.barista}/device/unblock`, { token: b2, device: 'C' })).status, 403);
  const r = await call('POST', `/users/${ids.barista}/device/unblock`, { token: mudurToken, device: 'M' });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal((await login('barista', 'A')).status, 200);
  // Yeni telefon hala yasak: tekrar bloke olur.
  assert.equal((await login('barista', 'B')).body.code, 'DEVICE_BLOCKED');
});

test('cihaz sifirlama: yeni telefona eslesir', { skip }, async () => {
  const r = await call('POST', `/users/${ids.barista}/device/reset`, { token: mudurToken, device: 'M' });
  assert.equal(r.status, 200);
  assert.equal((await login('barista', 'B')).status, 200);
  const row = await db.queryOne('SELECT device_id, device_blocked FROM users WHERE id = ?', ids.barista);
  assert.equal(row.device_id, 'B');
  assert.equal(Number(row.device_blocked), 0);
  const logs = await db.queryAll(
    "SELECT action FROM activity_logs WHERE action IN ('CIHAZ_SIFIRLA','CIHAZ_BLOKE_KALDIR') ORDER BY id");
  assert.deepEqual(logs.map((l) => l.action), ['CIHAZ_BLOKE_KALDIR', 'CIHAZ_SIFIRLA']);
});

test('baskasinin telefonunda eslesmemis hesap acilmaz ama bloke olmaz', { skip }, async () => {
  await db.execute('UPDATE users SET device_id = NULL WHERE id = ?', ids.barista2);
  const r = await login('barista2', 'B');
  assert.equal(r.status, 403);
  assert.equal(r.body.code, 'DEVICE_TAKEN');
  const row = await db.queryOne('SELECT device_id, device_blocked FROM users WHERE id = ?', ids.barista2);
  assert.equal(row.device_id, null);
  assert.equal(Number(row.device_blocked), 0);
});

test('web girisi eslesmeyi etkilemez; giris-cikis yalnizca kayitli telefondan', { skip }, async () => {
  const web = await login('barista', undefined);
  assert.equal(web.status, 200);
  const r = await call('POST', '/pdks/check-in', { token: web.body.token, body: {} });
  assert.equal(r.status, 403);
  assert.equal(r.body.code, 'DEVICE_REQUIRED');
  // Kayitli telefondan istek cihaz kapisini gecer (sonraki kontroller ayri).
  const tel = await call('POST', '/pdks/check-in', { token: web.body.token, device: 'B', body: {} });
  assert.notEqual(tel.body.code, 'DEVICE_REQUIRED');
});

test('ana yonetici eslestirme disinda', { skip }, async () => {
  assert.equal((await login('admin', 'P1')).status, 200);
  assert.equal((await login('admin', 'P2')).status, 200);
  const row = await db.queryOne('SELECT device_id FROM users WHERE id = ?', ids.admin);
  assert.equal(row.device_id, null);
});
