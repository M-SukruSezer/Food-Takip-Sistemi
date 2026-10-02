// Petty cash masraf duzenleme: kurallar silme ile ayni, limit kaydin kendi
// tutari geri eklenerek kontrol edilir. TEST_DATABASE_URL yoksa atlanir.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');

const URL = process.env.TEST_DATABASE_URL;
const skip = !URL && 'TEST_DATABASE_URL tanımlı değil';
let db, auth, server, base, ids;

before(async () => {
  if (skip) return;
  process.env.DATABASE_URL = URL;
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';
  require('express-async-errors');
  db = require('../src/db');
  auth = require('../src/auth');
  await db.initialize();
  await db.pool.query(`TRUNCATE petty_cash_expenses, petty_cash_limits, activity_logs,
    users, stores RESTART IDENTITY CASCADE`);
  const store = await db.queryOne("INSERT INTO stores (name) VALUES ('Test') RETURNING id");
  const user = async (n, role) => Number((await db.queryOne(`INSERT INTO users
    (store_id, username, password_hash, full_name, role) VALUES (?,?, 'x', ?, ?) RETURNING id`,
  store.id, n, n, role)).id);
  ids = { store: Number(store.id), mudur: await user('mudur', 'store_manager'), vs: await user('vs', 'shift_supervisor') };
  await db.execute('INSERT INTO petty_cash_limits (store_id, weekly_amount) VALUES (?, 500)', ids.store);
  const express = require('express');
  const app = express();
  app.use(express.json());
  app.use('/api', require('../src/routes'));
  app.use((err, req, res, next) => res.status(500).json({ error: err.message }));
  server = app.listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}/api/petty-cash`;
});
after(async () => {
  if (skip) return;
  await new Promise((r) => server.close(r));
  await db.pool.end();
});

async function call(who, method, path, body) {
  const role = who === 'mudur' ? 'store_manager' : 'shift_supervisor';
  const token = auth.sign({ id: ids[who], username: who, role, store_id: ids.store, full_name: who });
  const res = await fetch(base + path, {
    method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

test('bekleyen masrafı giren kişi düzenler; limit kendi tutarı geri eklenerek ölçülür', { skip }, async () => {
  const r = await call('vs', 'POST', '', { amount: 400, description: '[Teknik Bakım] Filtre' });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  // 400 kullanilmis, kalan 100; kayit kendisi geri eklenince 500'e kadar duzenlenebilir.
  let u = await call('vs', 'PUT', `/${r.body.id}`, { amount: 480, description: '[Teknik Bakım] Filtre ve conta' });
  assert.equal(u.status, 200, JSON.stringify(u.body));
  u = await call('vs', 'PUT', `/${r.body.id}`, { amount: 501, description: 'x' });
  assert.equal(u.status, 400);
  const row = await db.queryOne('SELECT amount, description FROM petty_cash_expenses WHERE id = ?', r.body.id);
  assert.equal(Number(row.amount), 480);
  assert.equal(row.description, '[Teknik Bakım] Filtre ve conta');
  // Listede kaydi girenin kimligi doner (arayuz kaydirma islemlerini buna gore acar).
  const list = await call('vs', 'GET', '');
  assert.equal(list.body.items[0].created_by, ids.vs);
});

test('başkasının ya da onaylı masraf düzenlenemez', { skip }, async () => {
  const r = await call('mudur', 'POST', '', { amount: 10, description: 'Süt' });
  assert.equal(r.status, 201);
  // Mudurun kaydi dogrudan onayli: kendisi de duzenleyemez, vardiya sorumlusu hic.
  assert.equal((await call('mudur', 'PUT', `/${r.body.id}`, { amount: 12 })).body.error, 'Onaylanmış masraf düzenlenemez');
  assert.equal((await call('vs', 'PUT', `/${r.body.id}`, { amount: 12 })).status, 403);
  assert.equal((await call('mudur', 'DELETE', `/${r.body.id}`)).body.error, 'Onaylanmış masraf silinemez');
});
