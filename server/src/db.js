const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const fs = require('fs');
const bcrypt = require('bcryptjs');

const dataDir = path.join(__dirname, '..', 'data');
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const db = new DatabaseSync(path.join(dataDir, 'app.db'));
db.exec('PRAGMA foreign_keys = ON;');
db.exec('PRAGMA journal_mode = WAL;');

db.exec(`
CREATE TABLE IF NOT EXISTS stores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('super_admin','store_manager','staff')),
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  FOREIGN KEY (store_id) REFERENCES stores(id)
);

CREATE TABLE IF NOT EXISTS product_types (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  skt_days INTEGER NOT NULL DEFAULT 3 CHECK (skt_days >= 1 AND skt_days <= 14),
  description TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  FOREIGN KEY (store_id) REFERENCES stores(id)
);

CREATE TABLE IF NOT EXISTS batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL,
  product_type_id INTEGER NOT NULL,
  batch_code TEXT,
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  remaining INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'frozen' CHECK (status IN ('frozen','thawing','food_cabinet','sold','discarded')),
  entered_frozen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  thawing_started_at TEXT,
  thawing_finish_at TEXT,
  food_cabinet_entered_at TEXT,
  skt_end TEXT,
  sold_at TEXT,
  discarded_at TEXT,
  discard_reason TEXT,
  notes TEXT,
  created_by INTEGER,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  FOREIGN KEY (store_id) REFERENCES stores(id),
  FOREIGN KEY (product_type_id) REFERENCES product_types(id)
);

CREATE TABLE IF NOT EXISTS sales (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL,
  batch_id INTEGER NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity >= 1),
  unit_price REAL,
  sold_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  sold_by INTEGER,
  FOREIGN KEY (store_id) REFERENCES stores(id),
  FOREIGN KEY (batch_id) REFERENCES batches(id)
);

CREATE TABLE IF NOT EXISTS activity_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER,
  user_id INTEGER,
  username TEXT,
  action TEXT NOT NULL,
  entity_type TEXT,
  entity_id INTEGER,
  details TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_batches_status ON batches(status);
CREATE INDEX IF NOT EXISTS idx_batches_store ON batches(store_id);
CREATE INDEX IF NOT EXISTS idx_batches_skt_end ON batches(skt_end);
CREATE INDEX IF NOT EXISTS idx_sales_batch ON sales(batch_id);
CREATE INDEX IF NOT EXISTS idx_sales_store ON sales(store_id);
CREATE INDEX IF NOT EXISTS idx_logs_store ON activity_logs(store_id);

CREATE TABLE IF NOT EXISTS transfer_approvals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_id INTEGER NOT NULL,
  store_id INTEGER NOT NULL,
  requested_by INTEGER,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  requested_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  decided_by INTEGER,
  decided_at TEXT,
  decision_note TEXT,
  FOREIGN KEY (batch_id) REFERENCES batches(id),
  FOREIGN KEY (store_id) REFERENCES stores(id)
);

CREATE INDEX IF NOT EXISTS idx_approvals_batch ON transfer_approvals(batch_id);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON transfer_approvals(status);
`);

// Migrasyon: product_types.store_id NULL olabilir (store_id NULL = genel çeşit, tüm mağazalar kullanabilir)
try {
  const col = db.prepare('PRAGMA table_info(product_types)').all().find((c) => c.name === 'store_id');
  if (col && col.notnull === 1) {
    db.exec('PRAGMA foreign_keys = OFF;');
    db.exec(`
      CREATE TABLE product_types_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id INTEGER,
        name TEXT NOT NULL,
        skt_days INTEGER NOT NULL DEFAULT 3 CHECK (skt_days >= 1 AND skt_days <= 14),
        description TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
        FOREIGN KEY (store_id) REFERENCES stores(id)
      );
      INSERT INTO product_types_new (id, store_id, name, skt_days, description, active, created_at)
        SELECT id, store_id, name, skt_days, description, active, created_at FROM product_types;
      DROP TABLE product_types;
      ALTER TABLE product_types_new RENAME TO product_types;
    `);
    db.exec('PRAGMA foreign_keys = ON;');
    console.log('Migrasyon: product_types.store_id artık NULL olabilir (genel çeşit desteği)');
  }
} catch (e) {
  console.error('Migrasyon hatası:', e.message);
}

function nowISO() {
  return new Date().toISOString();
}

function addHours(iso, hours) {
  return new Date(new Date(iso).getTime() + hours * 3600 * 1000).toISOString();
}

function addDays(iso, days) {
  return new Date(new Date(iso).getTime() + days * 24 * 3600 * 1000).toISOString();
}

function seed() {
  if (process.env.SEED_DEMO_DATA !== 'true') return;
  const count = db.prepare('SELECT COUNT(*) AS c FROM users').get().c;
  if (count > 0) return;

  const insertUser = db.prepare(
    'INSERT INTO users (store_id, username, password_hash, full_name, role, active) VALUES (?,?,?,?,?,1)'
  );

  insertUser.run(
    null,
    'admin',
    bcrypt.hashSync('admin123', 10),
    'Ana Yönetici',
    'super_admin'
  );

  const storeInsert = db.prepare(
    'INSERT INTO stores (name, address, phone) VALUES (?,?,?)'
  );
  const storeRes = storeInsert.run('Demo Mağaza', 'Örnek Cad. No:1, İstanbul', '0212 000 00 00');
  const storeId = Number(storeRes.lastInsertRowid);

  insertUser.run(storeId, 'mudur', bcrypt.hashSync('mudur123', 10), 'Mağaza Müdürü', 'store_manager');
  insertUser.run(storeId, 'personel', bcrypt.hashSync('personel123', 10), 'Mağaza Personeli', 'staff');

  const typeInsert = db.prepare(
    'INSERT INTO product_types (store_id, name, skt_days, description) VALUES (?,?,?,?)'
  );
  const t1 = typeInsert.run(storeId, 'Çikolatalı Pasta', 3, 'Çikolatalı ganaj kremalı pasta');
  const t2 = typeInsert.run(storeId, 'Vişneli Pasta', 4, 'Vişne soslu pasta');
  const t3 = typeInsert.run(storeId, 'Red Velvet Pasta', 3, 'Kadifemsi kırmızı kek');
  const t4 = typeInsert.run(storeId, 'Fıstıklı Pasta', 4, 'Antep fıstıklı pasta');
  // Genel çeşitler (Ana Yönetici tanımlı, tüm mağazalar kullanabilir)
  typeInsert.run(null, 'Klasik Yaş Pasta', 3, 'Genel katalog ürünü');
  typeInsert.run(null, 'Meyveli Pasta', 4, 'Genel katalog ürünü');

  const batchInsert = db.prepare(
    `INSERT INTO batches (store_id, product_type_id, batch_code, quantity, remaining, status,
      entered_frozen_at, thawing_started_at, thawing_finish_at, food_cabinet_entered_at, skt_end, created_by)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`
  );

  const frozenAt = new Date(Date.now() - 2 * 24 * 3600 * 1000).toISOString();
  const thawStart = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
  const thawFinish = addHours(thawStart, 8);
  const cabinetAt = new Date(Date.now() - 2 * 24 * 3600 * 1000).toISOString();

  batchInsert.run(storeId, t1.lastInsertRowid, 'DK-001', 12, 12, 'frozen', frozenAt, null, null, null, null, 1);
  batchInsert.run(storeId, t2.lastInsertRowid, 'DK-002', 8, 8, 'thawing', frozenAt, thawStart, thawFinish, null, null, 1);
  batchInsert.run(storeId, t3.lastInsertRowid, 'FD-003', 6, 6, 'food_cabinet', cabinetAt, cabinetAt, addHours(cabinetAt, 8), cabinetAt, addDays(cabinetAt, 3), 1);
  batchInsert.run(storeId, t4.lastInsertRowid, 'FD-004', 5, 5, 'food_cabinet', cabinetAt, cabinetAt, addHours(cabinetAt, 8), cabinetAt, addDays(cabinetAt, 4), 1);
  batchInsert.run(storeId, t1.lastInsertRowid, 'FD-005', 4, 4, 'food_cabinet', new Date(Date.now() - 5 * 24 * 3600 * 1000).toISOString(), null, null, new Date(Date.now() - 5 * 24 * 3600 * 1000).toISOString(), addDays(new Date(Date.now() - 5 * 24 * 3600 * 1000).toISOString(), 3), 1);

  const logInsert = db.prepare(
    'INSERT INTO activity_logs (store_id, user_id, username, action, entity_type, entity_id, details) VALUES (?,?,?,?,?,?,?)'
  );
  logInsert.run(storeId, 1, 'admin', 'SISTEM_HAZIR', 'system', null, 'Örnek veriler oluşturuldu');
}

function bootstrapAdmin() {
  const count = db.prepare('SELECT COUNT(*) AS c FROM users').get().c;
  const username = String(process.env.BOOTSTRAP_ADMIN_USERNAME || '').trim();
  const password = String(process.env.BOOTSTRAP_ADMIN_PASSWORD || '');
  const fullName = String(process.env.BOOTSTRAP_ADMIN_NAME || 'Ana Yonetici').trim();
  if (count > 0 || !username || password.length < 12) return;

  db.prepare(
    'INSERT INTO users (store_id, username, password_hash, full_name, role, active) VALUES (?,?,?,?,?,1)'
  ).run(null, username, bcrypt.hashSync(password, 10), fullName, 'super_admin');
  console.log(`Ilk yonetici hesabi olusturuldu: ${username}`);
}

seed();
bootstrapAdmin();

module.exports = { db, nowISO, addHours, addDays };
