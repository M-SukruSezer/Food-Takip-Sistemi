const { Pool } = require('pg');
const { types } = require('pg');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');

if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL zorunludur');

types.setTypeParser(20, Number);
types.setTypeParser(1700, Number);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' || process.env.DATABASE_URL.includes('supabase')
    ? { rejectUnauthorized: false }
    : undefined,
  max: Number(process.env.DB_POOL_MAX || 10),
});

function postgresSql(sql) {
  let index = 0;
  return sql.replace(/\?/g, () => `$${++index}`);
}

function normalizeParams(params) {
  return Array.isArray(params) ? params : [params];
}

async function query(sql, ...params) {
  const client = params.length > 0 && params[params.length - 1] && typeof params[params.length - 1].query === 'function'
    ? params.pop()
    : pool;
  const values = params.length === 1 && Array.isArray(params[0]) ? params[0] : normalizeParams(params);
  return client.query(postgresSql(sql), values);
}

async function queryAll(sql, ...params) {
  const result = await query(sql, ...params);
  return result.rows;
}

async function queryOne(sql, ...params) {
  const result = await query(sql, ...params);
  return result.rows[0];
}

async function execute(sql, ...params) {
  const result = await query(sql, ...params);
  return { changes: result.rowCount, lastInsertRowid: result.rows[0] && result.rows[0].id };
}

async function transaction(callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
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

async function seed() {
  if (process.env.SEED_DEMO_DATA !== 'true') return;
  const count = Number((await queryOne('SELECT COUNT(*) AS c FROM users')).c);
  if (count > 0) return;
  await transaction(async (client) => {
    const insertUser = 'INSERT INTO users (store_id, username, password_hash, full_name, role, active) VALUES (?,?,?,?,?,1)';
    await execute(insertUser, [null, 'admin', bcrypt.hashSync('admin123', 10), 'Ana Yönetici', 'super_admin'], client);
    const storeRes = await queryOne('INSERT INTO stores (name, address, phone) VALUES (?,?,?) RETURNING id', ['Demo Mağaza', 'Örnek Cad. No:1, İstanbul', '0212 000 00 00'], client);
    const storeId = Number(storeRes.id);
    await execute(insertUser, [storeId, 'mudur', bcrypt.hashSync('mudur123', 10), 'Mağaza Müdürü', 'store_manager'], client);
    await execute(insertUser, [storeId, 'personel', bcrypt.hashSync('personel123', 10), 'Mağaza Personeli', 'staff'], client);
    const typeInsert = 'INSERT INTO product_types (store_id, name, skt_days, description) VALUES (?,?,?,?) RETURNING id';
    const t1 = await queryOne(typeInsert, [storeId, 'Çikolatalı Pasta', 3, 'Çikolatalı ganaj kremalı pasta'], client);
    const t2 = await queryOne(typeInsert, [storeId, 'Vişneli Pasta', 4, 'Vişne soslu pasta'], client);
    const t3 = await queryOne(typeInsert, [storeId, 'Red Velvet Pasta', 3, 'Kadifemsi kırmızı kek'], client);
    const t4 = await queryOne(typeInsert, [storeId, 'Fıstıklı Pasta', 4, 'Antep fıstıklı pasta'], client);
  // Genel çeşitler (Ana Yönetici tanımlı, tüm mağazalar kullanabilir)
    await execute(typeInsert, [null, 'Klasik Yaş Pasta', 3, 'Genel katalog ürünü'], client);
    await execute(typeInsert, [null, 'Meyveli Pasta', 4, 'Genel katalog ürünü'], client);

    const batchInsert =
    `INSERT INTO batches (store_id, product_type_id, batch_code, quantity, remaining, status,
      entered_frozen_at, thawing_started_at, thawing_finish_at, food_cabinet_entered_at, skt_end, created_by)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`
    ;

  const frozenAt = new Date(Date.now() - 2 * 24 * 3600 * 1000).toISOString();
  const thawStart = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
  const thawFinish = addHours(thawStart, 8);
  const cabinetAt = new Date(Date.now() - 2 * 24 * 3600 * 1000).toISOString();

    const addBatch = async (values) => execute(`${batchInsert} RETURNING id`, values, client);
    await addBatch([storeId, t1.id, 'DK-001', 12, 12, 'frozen', frozenAt, null, null, null, null, 1]);
    await addBatch([storeId, t2.id, 'DK-002', 8, 8, 'thawing', frozenAt, thawStart, thawFinish, null, null, 1]);
    await addBatch([storeId, t3.id, 'FD-003', 6, 6, 'food_cabinet', cabinetAt, cabinetAt, addHours(cabinetAt, 8), cabinetAt, addDays(cabinetAt, 3), 1]);
    await addBatch([storeId, t4.id, 'FD-004', 5, 5, 'food_cabinet', cabinetAt, cabinetAt, addHours(cabinetAt, 8), cabinetAt, addDays(cabinetAt, 4), 1]);
    const old = new Date(Date.now() - 5 * 24 * 3600 * 1000).toISOString();
    await addBatch([storeId, t1.id, 'FD-005', 4, 4, 'food_cabinet', old, null, null, old, addDays(old, 3), 1]);

    await execute('INSERT INTO activity_logs (store_id, user_id, username, action, entity_type, entity_id, details) VALUES (?,?,?,?,?,?,?)', [storeId, 1, 'admin', 'SISTEM_HAZIR', 'system', null, 'Örnek veriler oluşturuldu'], client);
  });
}

async function bootstrapAdmin() {
  const count = Number((await queryOne('SELECT COUNT(*) AS c FROM users')).c);
  const username = String(process.env.BOOTSTRAP_ADMIN_USERNAME || '').trim();
  const password = String(process.env.BOOTSTRAP_ADMIN_PASSWORD || '');
  const fullName = String(process.env.BOOTSTRAP_ADMIN_NAME || 'Ana Yonetici').trim();
  if (count > 0 || !username || password.length < 12) return;

  await execute('INSERT INTO users (store_id, username, password_hash, full_name, role, active) VALUES (?,?,?,?,?,1)', [null, username, bcrypt.hashSync(password, 10), fullName, 'super_admin']);
  console.log(`Ilk yonetici hesabi olusturuldu: ${username}`);
}

async function initialize() {
  const schema = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'schema.sql'), 'utf8');
  await pool.query(schema);
  await seed();
  await bootstrapAdmin();
}

module.exports = { pool, query, queryAll, queryOne, execute, transaction, initialize, nowISO, addHours, addDays };
