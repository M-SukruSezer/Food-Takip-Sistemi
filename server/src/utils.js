const { queryAll, queryOne, execute, nowISO } = require('./db');

async function logActivity(user, action, entityType, entityId, details, storeId) {
  const sid = storeId !== undefined ? storeId : (user && user.store_id) || null;
  await execute(
    'INSERT INTO activity_logs (store_id, user_id, username, action, entity_type, entity_id, details) VALUES (?,?,?,?,?,?,?)'
  ,sid, user ? user.id : null, user ? user.username : 'sistem', action, entityType, entityId, details || null);
}

const STATUS_LABELS = {
  frozen: 'Donuk Depo',
  thawing: 'Çözülme (+4°C)',
  food_cabinet: 'Food Dolabı',
  sold: 'Satıldı',
  discarded: 'İmha Edildi',
};

function batchRow(row) {
  if (!row) return null;
  const now = Date.now();
  let remainingHours = null;
  let urgency = null;
  if (row.status === 'food_cabinet' && row.skt_end) {
    remainingHours = Math.floor((new Date(row.skt_end).getTime() - now) / 3600000);
    if (remainingHours <= 0) urgency = 'expired';
    else if (remainingHours <= 24) urgency = 'critical';
    else if (remainingHours <= 48) urgency = 'warning';
    else urgency = 'normal';
  }
  let thawRemainingHours = null;
  if (row.status === 'thawing' && row.thawing_finish_at) {
    thawRemainingHours = Math.max(0, Math.ceil((new Date(row.thawing_finish_at).getTime() - now) / 3600000));
  }
  return {
    ...row,
    status_label: STATUS_LABELS[row.status] || row.status,
    remaining_hours: remainingHours,
    urgency,
    thaw_remaining_hours: thawRemainingHours,
    thaw_ready: row.status === 'thawing' && thawRemainingHours === 0,
  };
}

function requireStoreAccessForBatch(storeId, user) {
  if (user.role !== 'super_admin' && storeId !== user.store_id) {
    const err = new Error('Bu ürüne erişim yetkiniz yok');
    err.status = 403;
    throw err;
  }
}

// Cozulme suresi (8 saat) dolan partileri food dolabina tasir.
//
// Vercel'de sunucu istek basina ayaga kalktigi icin surekli calisan bir
// zamanlayici yok; bu yuzden terfi, listeleri okuyan uc noktalarin basinda
// calisir. Personel uygulamayi surekli kullandigi icin pratikte suresi dolan
// parti ilk bakista dolaba gecmis olur.
//
// Kritik ayrinti: food_cabinet_entered_at ve skt_end, terfinin CALISTIGI an
// degil partinin gercekten hazir oldugu an (thawing_finish_at) uzerinden
// yazilir. Aksi halde uygulama 12 saat acilmazsa SKT 12 saat ileri kayar ve
// urun oldugundan taze gorunur.
//
// Tek ifadede yapildigi icin ayni anda gelen iki istek ayni partiyi iki kez
// tasiyamaz: ikinci istek status = 'thawing' kosuluna takilir.
async function promoteReadyThawing() {
  const promoted = await queryAll(`
    UPDATE batches b
    SET status = 'food_cabinet',
        food_cabinet_entered_at = b.thawing_finish_at,
        skt_end = to_char(
          (b.thawing_finish_at::timestamptz + (pt.skt_days || ' days')::interval) AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
        )
    FROM product_types pt
    WHERE pt.id = b.product_type_id
      AND b.status = 'thawing'
      AND b.thawing_finish_at IS NOT NULL
      AND b.thawing_finish_at <= ?
    RETURNING b.id, b.store_id, b.skt_end, pt.name AS product_name
  `, nowISO());

  for (const row of promoted) {
    await logActivity(null, 'FOOD_DOLABI_OTOMATIK', 'batch', row.id,
      `${row.product_name} çözülme süresi dolduğu için otomatik food dolabına alındı, SKT: ${new Date(row.skt_end).toLocaleString('tr-TR')}`,
      row.store_id);
    const cancelled = await execute(
      "UPDATE transfer_approvals SET status = 'cancelled', decided_at = ?, decision_note = ? WHERE batch_id = ? AND status = 'pending'",
      nowISO(), 'Çözülme süresi doldu, otomatik aktarım yapıldı', row.id
    );
    if (cancelled.changes > 0) {
      await logActivity(null, 'TRANSFER_IPTAL', 'batch', row.id, 'Bekleyen erken aktarım isteği kapatıldı', row.store_id);
    }
  }
  return promoted.length;
}

module.exports = { logActivity, batchRow, requireStoreAccessForBatch, promoteReadyThawing };
