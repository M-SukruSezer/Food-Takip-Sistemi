// Vardiya plani notlari: magaza basina, haftalar arasinda sabit; yalnizca yonetici yazar,
// cizelgeyi goren okur. TEST_DATABASE_URL yoksa atlanir.
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
  await db.pool.query('TRUNCATE roster_notes, activity_logs, users, stores RESTART IDENTITY CASCADE');
  const a = await db.queryOne("INSERT INTO stores (name) VALUES ('A') RETURNING id");
  const b = await db.queryOne("INSERT INTO stores (name) VALUES ('B') RETURNING id");
  const user = async (n, role, s) => Number((await db.queryOne(`INSERT INTO users
    (store_id, username, password_hash, full_name, role) VALUES (?,?, 'x', ?, ?) RETURNING id`,
  s, n, n, role)).id);
  ids = {
    a: Number(a.id), b: Number(b.id),
    mudur: await user('mudur', 'store_manager', a.id),
    barista: await user('barista', 'barista', a.id),
  };
  const express = require('express');
  const app = express();
  app.use(express.json());
  app.use('/api', require('../src/routes'));
  app.use((err, req, res, next) => res.status(500).json({ error: err.message }));
  server = app.listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}/api/pdks/roster/notes`;
});
after(async () => {
  if (skip) return;
  await new Promise((r) => server.close(r));
  await db.pool.end();
});

async function call(who, method, path, body) {
  const role = who === 'mudur' ? 'store_manager' : 'barista';
  const token = auth.sign({ id: ids[who], username: who, role, store_id: ids.a, full_name: who });
  const res = await fetch(base + path, {
    method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

test('müdür not ekler, düzenler, siler; not her haftada görünür; kayıt düşer', { skip }, async () => {
  // 2026-10-07 carsamba -> hafta 2026-10-05.
  const r = await call('mudur', 'POST', '', { from: '2026-10-07', body: 'Pazar envanter sayımı' });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  assert.equal(r.body.week_start, '2026-10-05');
  let list = await call('barista', 'GET', '?from=2026-10-05');
  assert.equal(list.body.length, 1);
  assert.equal(list.body[0].created_by_name, 'mudur');

  assert.equal((await call('mudur', 'PUT', `/${r.body.id}`, { body: 'Cumartesi sayım' })).status, 200);
  // Baska haftaya gecince de ayni not gorunur.
  list = await call('mudur', 'GET', '?from=2026-11-16');
  assert.equal(list.body.length, 1);
  assert.equal(list.body[0].body, 'Cumartesi sayım');
  assert.equal(list.body[0].updated_by_name, 'mudur');

  assert.equal((await call('mudur', 'DELETE', `/${r.body.id}`)).status, 200);
  assert.equal((await call('mudur', 'GET', '?from=2026-10-05')).body.length, 0);
  // Tarihsiz not da eklenir; tarihsiz okuma da calisir.
  const t = await call('mudur', 'POST', '', { body: 'Genel not' });
  assert.equal(t.status, 201, JSON.stringify(t.body));
  assert.equal((await call('barista', 'GET', '')).body.length, 1);
  await call('mudur', 'DELETE', `/${t.body.id}`);
  const logs = await db.queryAll("SELECT action FROM activity_logs WHERE entity_type = 'roster_note' ORDER BY id");
  assert.deepEqual(logs.map((l) => l.action),
    ['CIZELGE_NOT_EKLE', 'CIZELGE_NOT_DUZENLE', 'CIZELGE_NOT_SIL', 'CIZELGE_NOT_EKLE', 'CIZELGE_NOT_SIL']);
});

test('barista yazamaz, boş not ve başka mağaza reddedilir', { skip }, async () => {
  assert.equal((await call('barista', 'POST', '', { from: '2026-10-05', body: 'x' })).status, 403);
  assert.equal((await call('mudur', 'POST', '', { from: '2026-10-05', body: '  ' })).status, 400);
  assert.equal((await call('mudur', 'POST', '', { from: '2026-10-05', body: 'x', storeId: ids.b })).status, 403);
});
