const { queryOne, execute, transaction } = require('../db');
const { activeStatusOf, logActivity } = require('../utils');

// Geriye donuk adet duzeltmesi.
//
// Satis, ikram ve zayi kayitlarinda adet yanlis girildiginde kaydi silmek
// yerine adedi duzeltmek gerekiyor: rapor paneli food rakamlarini bu
// kayitlardan CANLI hesapladigi icin duzeltme gecmis raporlara da yansiyor.
//
// Duzeltmenin iki yonu var:
//   adet azaltilirsa  -> fark partinin kalan stoguna geri eklenir
//   adet artirilirsa  -> fark partinin kalan stogundan dusulur (yeterliyse)
//
// Parti tamamen tukendigi icin 'sold' veya 'discarded' olmussa, stok geri
// gelince durum surecin geldigi yere dondurulur (activeStatusOf).

/// Adet degisimini partiye uygular. Hata varsa {error} doner.
///
/// `delta` pozitifse partiye geri eklenir, negatifse partiden dusulur.
async function applyStockDelta(batch, delta, client) {
  if (delta === 0) return {};
  if (delta < 0 && batch.remaining < -delta) {
    return { error: `Yeterli stok yok. Kalan: ${batch.remaining}` };
  }

  const nextRemaining = batch.remaining + delta;
  // Stok geri geldiyse ve parti tukenmis sayiliyorsa durum geri alinir.
  const revive = delta > 0 && ['sold', 'discarded'].includes(batch.status);
  if (revive) {
    const status = activeStatusOf(batch);
    await execute(
      `UPDATE batches SET remaining = ?, status = ?,
         sold_at = CASE WHEN ? = 'sold' THEN NULL ELSE sold_at END,
         discarded_at = CASE WHEN ? = 'discarded' THEN NULL ELSE discarded_at END,
         discard_reason = CASE WHEN ? = 'discarded' THEN NULL ELSE discard_reason END
       WHERE id = ?`,
      [nextRemaining, status, batch.status, batch.status, batch.status, batch.id], client
    );
    return { revivedTo: status, remaining: nextRemaining };
  }

  // Adet artirilirken parti tamamen tukenirse durum kapatilir.
  if (nextRemaining === 0 && ['frozen', 'thawing', 'food_cabinet'].includes(batch.status)) {
    return { remaining: 0, exhausted: true };
  }
  await execute('UPDATE batches SET remaining = ? WHERE id = ?', [nextRemaining, batch.id], client);
  return { remaining: nextRemaining };
}

/// Girilen adedi dogrular.
function readQuantity(raw) {
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) return { error: 'Miktar en az 1 olmalıdır' };
  return { quantity: n };
}

/// Satis, ikram veya zayi kaydinin adedini duzeltir.
///
/// `table` 'sales' | 'discards', `qtyColumn` her ikisinde de 'quantity'.
async function correctRecord({ table, record, batch, newQuantity, req, extra = {} }) {
  const delta = record.quantity - newQuantity;
  let result = {};
  let failure = null;

  await transaction(async (client) => {
    result = await applyStockDelta(batch, delta, client);
    if (result.error) { failure = result.error; return; }

    // Adet artisi partiyi tuketirse durumu da kapatmak gerekir.
    if (result.exhausted) {
      const closedStatus = table === 'sales' ? 'sold' : 'discarded';
      const stampColumn = table === 'sales' ? 'sold_at' : 'discarded_at';
      await execute(
        `UPDATE batches SET remaining = 0, status = ?, ${stampColumn} = COALESCE(${stampColumn}, ?) WHERE id = ?`,
        [closedStatus, new Date().toISOString(), batch.id], client
      );
    }

    const sets = ['quantity = ?'];
    const params = [newQuantity];
    for (const [col, val] of Object.entries(extra)) {
      sets.push(`${col} = ?`);
      params.push(val);
    }
    params.push(record.id);
    await execute(`UPDATE ${table} SET ${sets.join(', ')} WHERE id = ?`, params, client);
  });

  if (failure) return { error: failure };
  return { ok: true, delta, ...result };
}

/// Satis, ikram veya zayi kaydini tamamen siler; adedin tamami stoga doner.
async function deleteRecord({ table, record, batch, client: outer }) {
  const run = async (client) => {
    await applyStockDelta(batch, record.quantity, client);
    await execute(`DELETE FROM ${table} WHERE id = ?`, [record.id], client);
  };
  if (outer) return run(outer);
  return transaction(run);
}

/// Parti ve ona bagli tum kayitlari siler. Yalnizca ana yonetici.
///
/// Bagli satir birakilamaz: sales ve discards partiye yabanci anahtarla bagli,
/// once onlar silinmeli.
async function deleteBatchCascade(batch, req) {
  let counts = { sales: 0, discards: 0, approvals: 0 };
  await transaction(async (client) => {
    const s = await execute('DELETE FROM sales WHERE batch_id = ?', [batch.id], client);
    const d = await execute('DELETE FROM discards WHERE batch_id = ?', [batch.id], client);
    const a = await execute('DELETE FROM transfer_approvals WHERE batch_id = ?', [batch.id], client);
    counts = { sales: s.changes || 0, discards: d.changes || 0, approvals: a.changes || 0 };
    await execute('DELETE FROM batches WHERE id = ?', [batch.id], client);
  });
  return counts;
}

module.exports = {
  applyStockDelta, readQuantity, correctRecord, deleteRecord, deleteBatchCascade,
};
