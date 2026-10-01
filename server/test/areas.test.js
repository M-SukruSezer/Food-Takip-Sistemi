// Alan kapısı: mağaza hesabı yalnızca Operasyon & Denetim'e, barista yalnızca
// PDKS & Kadro'ya girer. Kapı requireAuth içinde olduğu için gerçek ara katman
// gerçek JWT ile denenir; yalnızca veritabanı taklit edilir.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

let lastLogType = 'GIRIS';
require.cache[require.resolve('../src/db')] = { exports: {
  queryAll: async () => [],
  // shiftState sorgusu (yalnızca vardiya sorumlusu için çalışır).
  queryOne: async () => ({ pdks_enabled: 1, last_type: lastLogType }),
} };

const auth = require('../src/auth');

let server, base;
before(async () => {
  const app = express();
  const ok = (req, res) => res.json({ ok: true, role: req.user.role });
  // Gerçek uygulamadaki gibi her korunan yönlendirici requireAuth ile başlar.
  app.get('/api/auth/me', auth.requireAuth, ok);
  app.get('/api/stores', auth.requireAuth, ok);
  app.post('/api/stores', auth.requireAuth, ok);
  app.get('/api/batches', auth.requireAuth, ok);
  app.post('/api/sales', auth.requireAuth, ok);
  app.get('/api/dashboard', auth.requireAuth, ok);
  app.get('/api/pdks/me', auth.requireAuth, ok);
  app.get('/api/pdks/roster', auth.requireAuth, ok);
  app.get('/api/pdks/notifications', auth.requireAuth, ok);
  server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/api`;
});
after(() => new Promise((resolve) => server.close(resolve)));

function call(role, method, path) {
  const token = auth.sign({ id: 7, username: 'u', role, store_id: 1, full_name: 'Test' });
  return fetch(base + path, { method, headers: { authorization: `Bearer ${token}` } });
}

test('mağaza hesabı operasyon alanına girer', async () => {
  for (const [m, p] of [['GET', '/batches'], ['POST', '/sales'], ['GET', '/dashboard']]) {
    assert.equal((await call('store', m, p)).status, 200, `${m} ${p}`);
  }
});

test('mağaza hesabı PDKS & Kadro alanına giremez', async () => {
  for (const p of ['/pdks/me', '/pdks/roster', '/pdks/notifications']) {
    const r = await call('store', 'GET', p);
    assert.equal(r.status, 403, p);
    assert.equal((await r.json()).code, 'AREA_FORBIDDEN');
  }
});

test('barista PDKS & Kadro alanına girer', async () => {
  for (const p of ['/pdks/me', '/pdks/roster', '/pdks/notifications']) {
    assert.equal((await call('barista', 'GET', p)).status, 200, p);
  }
});

test('barista operasyon alanına giremez (mesai açık olsa bile)', async () => {
  lastLogType = 'GIRIS';
  for (const [m, p] of [['GET', '/batches'], ['POST', '/sales'], ['GET', '/dashboard'], ['POST', '/stores']]) {
    const r = await call('barista', m, p);
    assert.equal(r.status, 403, `${m} ${p}`);
    assert.equal((await r.json()).code, 'AREA_FORBIDDEN');
  }
});

test('ortak yollar iki role de açık (oturum, mağaza adı)', async () => {
  for (const role of ['store', 'barista']) {
    assert.equal((await call(role, 'GET', '/auth/me')).status, 200, role);
    assert.equal((await call(role, 'GET', '/stores')).status, 200, role);
  }
});

test('diğer roller iki alana da girer; vardiya sorumlusunda mesai şartı sürer', async () => {
  for (const role of ['store_manager', 'regional_manager', 'super_admin']) {
    assert.equal((await call(role, 'GET', '/batches')).status, 200, role);
    assert.equal((await call(role, 'GET', '/pdks/roster')).status, 200, role);
  }
  lastLogType = 'GIRIS';
  assert.equal((await call('shift_supervisor', 'GET', '/batches')).status, 200);
  lastLogType = 'CIKIS';
  const r = await call('shift_supervisor', 'GET', '/batches');
  assert.equal(r.status, 403);
  assert.equal((await r.json()).code, 'SHIFT_REQUIRED');
});

test('mağaza müdürü mağaza hesabı tanımlayabilir; mağaza hesabı kimseyi tanımlayamaz', () => {
  assert.ok(auth.assignableRoles('store_manager').includes('store'));
  assert.deepEqual(auth.assignableRoles('store'), []);
});

test('PDKS personel filtresi mağaza hesabını dışlar', () => {
  assert.equal(auth.personnelOnly(), "AND u.role NOT IN ('store')");
  assert.equal(auth.personnelOnly(''), "AND role NOT IN ('store')");
});

// schema.sql her soğuk başlangıçta baştan çalışır. Rol kısıtının herhangi bir
// adımı güncel rol listesinden eksik kalırsa, o roldeki ilk kayıt açıldığı
// anda başlatma 23514 ile düşer ve API "Sistem başlatılıyor" (503) döner.
test('schema.sql içindeki her rol kısıtı tüm rolleri içerir', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const sql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'schema.sql'), 'utf8');
  // CREATE TABLE içindeki ilk kısıt yalnızca boş veritabanında bir kez
  // çalışır ve hemen ardından yeniden kurulur; her açılışta çalışan adım
  // ADD CONSTRAINT olduğu için o denetlenir.
  const checks = [...sql.matchAll(/ADD CONSTRAINT users_role_check CHECK \(role IN \(([^)]*)\)\)/g)];
  assert.ok(checks.length >= 1, 'rol kısıtı bulunamadı');
  for (const m of checks) {
    const roles = m[1].match(/'([^']+)'/g).map((r) => r.slice(1, -1));
    for (const role of auth.ROLES) {
      assert.ok(roles.includes(role), `"${role}" rolü şu kısıtta eksik: ${m[0].slice(0, 80)}…`);
    }
  }
});
