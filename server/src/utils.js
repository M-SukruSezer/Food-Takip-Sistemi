const { db } = require('./db');

function logActivity(user, action, entityType, entityId, details, storeId) {
  const sid = storeId !== undefined ? storeId : (user && user.store_id) || null;
  db.prepare(
    'INSERT INTO activity_logs (store_id, user_id, username, action, entity_type, entity_id, details) VALUES (?,?,?,?,?,?,?)'
  ).run(sid, user ? user.id : null, user ? user.username : 'sistem', action, entityType, entityId, details || null);
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

module.exports = { logActivity, batchRow, requireStoreAccessForBatch };
