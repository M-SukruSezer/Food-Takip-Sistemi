// Takas / haftalik OFF / rapor talepleri gercek PostgreSQL uzerinde uctan uca:
// talep -> karsi taraf onayi -> mudur onayi -> haftalik cizelge degisir.
//
// Veritabani ister; TEST_DATABASE_URL tanimli degilse atlanir. Yerelde:
//   TEST_DATABASE_URL=postgres://postgres@localhost:5432/foodtest npm test
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');

const URL = process.env.TEST_DATABASE_URL;
const skip = !URL && 'TEST_DATABASE_URL tanımlı değil';

let db, auth, server, base, ids;

function gun(offset) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
}
// Gelecek haftanin pazartesisi ve sonraki gunler.
const pzt = (() => {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + 7 - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
})();
const sonra = (n) => {
  const d = new Date(`${pzt}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};

before(async () => {
  if (skip) return;
  process.env.DATABASE_URL = URL;
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';
  require('express-async-errors');
  db = require('../src/db');
  auth = require('../src/auth');
  // Sema her soguk baslatmada yeniden calisiyor: iki kez calismasi hatasiz olmali.
  await db.initialize();
  await db.initialize();

  await db.pool.query(`TRUNCATE personnel_requests, user_shifts, shifts, activity_logs,
    users, stores RESTART IDENTITY CASCADE`);
  const store = await db.queryOne("INSERT INTO stores (name) VALUES ('Test') RETURNING id");
  const user = async (name, role) => Number((await db.queryOne(`
    INSERT INTO users (store_id, username, password_hash, full_name, role)
    VALUES (?, ?, 'x', ?, ?) RETURNING id`, store.id, name, name, role)).id);
  ids = {
    store: Number(store.id),
    mudur: await user('mudur', 'store_manager'),
    a: await user('ali', 'barista'),
    b: await user('ayse', 'barista'),
  };
  const shift = async (name, s, e) => Number((await db.queryOne(`
    INSERT INTO shifts (store_id, name, start_time, end_time) VALUES (?,?,?,?) RETURNING id`,
  store.id, name, s, e)).id);
  ids.sabah = await shift('Sabah', '08:00', '16:00');
  ids.aksam = await shift('Akşam', '16:00', '00:00');

  const express = require('express');
  const app = express();
  app.use(express.json({ limit: '4mb' }));
  app.use('/api', require('../src/routes'));
  app.use((err, req, res, next) => res.status(500).json({ error: err.message }));
  server = app.listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}/api/pdks`;
});

after(async () => {
  if (skip) return;
  await new Promise((r) => server.close(r));
  await db.pool.end();
});

async function call(who, method, path, body) {
  const roles = { mudur: 'store_manager', a: 'barista', b: 'barista' };
  const token = auth.sign({
    id: ids[who], username: who, role: roles[who], store_id: ids.store, full_name: who,
  });
  const res = await fetch(base + path, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

async function plan(userId, date, shiftId) {
  await db.execute(`INSERT INTO user_shifts (user_id, shift_id, work_date, is_day_off)
    VALUES (?, ?, ?, ?)`, userId, shiftId, date, shiftId ? 0 : 1);
}
async function cizelge(userId, date) {
  const rows = await db.queryAll(`SELECT shift_id, is_day_off, note FROM user_shifts
    WHERE user_id = ? AND work_date = ? ORDER BY shift_id`, userId, date);
  return rows.map((r) => (r.is_day_off ? (r.note || 'OFF') : Number(r.shift_id)));
}

test('vardiya takası: iki gün, karşı taraf + müdür onayıyla çizelge yer değiştirir',
  { skip }, async () => {
    const d1 = sonra(0);
    const d2 = sonra(1);
    await plan(ids.a, d1, ids.sabah); // Ali pazartesi sabah
    await plan(ids.b, d1, null); //       Ayşe pazartesi OFF
    await plan(ids.b, d2, ids.aksam); //  Ayşe salı akşam
    await plan(ids.a, d2, null); //       Ali salı OFF

    const r = await call('a', 'POST', '/requests', {
      type: 'VARDIYA_TAKAS', shift_date: d1, target_shift_date: d2,
      target_user_id: ids.b, reason: 'Okul',
    });
    assert.equal(r.status, 201, JSON.stringify(r.body));

    // Karsi taraf onaylamadan mudur onaylayamaz.
    let k = await call('mudur', 'POST', `/requests/${r.body.id}/approve`, {});
    assert.equal(k.status, 400);
    assert.equal((await call('b', 'POST', `/requests/${r.body.id}/confirm`)).status, 200);
    k = await call('mudur', 'POST', `/requests/${r.body.id}/approve`, {});
    assert.equal(k.status, 200, JSON.stringify(k.body));

    assert.deepEqual(await cizelge(ids.a, d1), ['OFF']);
    assert.deepEqual(await cizelge(ids.b, d1), [ids.sabah]);
    assert.deepEqual(await cizelge(ids.a, d2), [ids.aksam]);
    assert.deepEqual(await cizelge(ids.b, d2), ['OFF']);
  });

test('vardiya takası: aynı gün, ortak vardiya yerinde kalır', { skip }, async () => {
  const d = sonra(2);
  await plan(ids.a, d, ids.sabah);
  await plan(ids.b, d, ids.aksam);
  const r = await call('a', 'POST', '/requests', {
    type: 'VARDIYA_TAKAS', shift_date: d, target_user_id: ids.b, reason: 'Randevu',
  });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  await call('b', 'POST', `/requests/${r.body.id}/confirm`);
  const k = await call('mudur', 'POST', `/requests/${r.body.id}/approve`, {});
  assert.equal(k.status, 200, JSON.stringify(k.body));
  assert.deepEqual(await cizelge(ids.a, d), [ids.aksam]);
  assert.deepEqual(await cizelge(ids.b, d), [ids.sabah]);
});

test('haftalık OFF: eski OFF günüyle yer değiştirir, müdür onayına kadar çizelge aynı',
  { skip }, async () => {
    const yeni = sonra(3);
    const eski = sonra(4);
    await plan(ids.a, yeni, ids.sabah);
    await plan(ids.a, eski, null);

    const r = await call('a', 'POST', '/requests', {
      type: 'HAFTALIK_OFF', shift_date: yeni, target_shift_date: eski,
    });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.deepEqual(await cizelge(ids.a, yeni), [ids.sabah]);

    const k = await call('mudur', 'POST', `/requests/${r.body.id}/approve`, {});
    assert.equal(k.status, 200, JSON.stringify(k.body));
    assert.deepEqual(await cizelge(ids.a, yeni), ['OFF']);
    assert.deepEqual(await cizelge(ids.a, eski), [ids.sabah]);

    // Zaten OFF olan gun icin talep acilamaz; baska haftadaki gun takas edilemez.
    const tekrar = await call('a', 'POST', '/requests', { type: 'HAFTALIK_OFF', shift_date: yeni });
    assert.equal(tekrar.status, 400);
    const haftaDisi = await call('a', 'POST', '/requests', {
      type: 'HAFTALIK_OFF', shift_date: eski, target_shift_date: sonra(10),
    });
    assert.equal(haftaDisi.status, 400);
  });

test('rapor: görselsiz reddedilir; onaylanınca günler RAPOR olur, görsel listede taşınmaz',
  { skip }, async () => {
    const from = sonra(5);
    const to = sonra(6);
    await plan(ids.b, from, ids.sabah);
    await plan(ids.b, to, ids.aksam);

    const gorselsiz = await call('b', 'POST', '/requests', {
      type: 'RAPOR', start_at: from, end_at: to,
    });
    assert.equal(gorselsiz.status, 400);

    const img = 'data:image/jpeg;base64,' + Buffer.from('rapor').toString('base64');
    const r = await call('b', 'POST', '/requests', {
      type: 'RAPOR', start_at: from, end_at: to, attachment: img,
    });
    assert.equal(r.status, 201, JSON.stringify(r.body));

    const liste = await call('b', 'GET', '/requests');
    const satir = liste.body.find((x) => x.id === r.body.id);
    assert.equal(satir.has_attachment, true);
    assert.equal(satir.attachment, undefined);

    // Gorseli sahibi ve mudur gorur, baska personel goremez.
    assert.equal((await call('b', 'GET', `/requests/${r.body.id}/attachment`)).body.data_url, img);
    assert.equal((await call('mudur', 'GET', `/requests/${r.body.id}/attachment`)).status, 200);
    assert.equal((await call('a', 'GET', `/requests/${r.body.id}/attachment`)).status, 403);

    const k = await call('mudur', 'POST', `/requests/${r.body.id}/approve`, {});
    assert.equal(k.status, 200, JSON.stringify(k.body));
    assert.deepEqual(await cizelge(ids.b, from), ['RAPOR']);
    assert.deepEqual(await cizelge(ids.b, to), ['RAPOR']);
  });

test('geçmiş tarihli takas talebi reddedilir', { skip }, async () => {
  const dun = gun(-1);
  await plan(ids.a, dun, ids.sabah);
  const r = await call('a', 'POST', '/requests', {
    type: 'VARDIYA_TAKAS', shift_date: dun, target_user_id: ids.b, reason: 'x',
  });
  assert.equal(r.status, 400);
});
