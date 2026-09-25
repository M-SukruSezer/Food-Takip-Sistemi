const { queryAll, queryOne, execute } = require('../db');

// KVKK: ham konum koordinatlarinin saklama suresi.
//
// Devam kaydinin KENDISI silinmiyor — puantaj ve ucret dayanagi olarak
// saklanmasi gerekiyor. Silinen yalnizca ham enlem/boylam. Karar icin gereken
// ozet (distance_m, is_valid_location) kaliyor, boylece gecmis bir giris
// "isyerinde miydi" sorusuna koordinat olmadan da cevap verilebiliyor.
//
// Varsayilan 90 gun: amac devam dogrulamasi ve kisa vadeli itiraz incelemesi.
// Ucret kayitlarinin yillarca saklanmasi gerekmesi ham koordinatin da
// saklanmasini gerektirmiyor (amacla sinirlilik ilkesi).
const DEFAULT_RETENTION_DAYS = 90;

function retentionDays() {
  const n = Number(process.env.PDKS_COORD_RETENTION_DAYS);
  if (Number.isInteger(n) && n >= 1 && n <= 3650) return n;
  return DEFAULT_RETENTION_DAYS;
}

function cutoffIso(days = retentionDays()) {
  return new Date(Date.now() - days * 24 * 3600 * 1000).toISOString();
}

/// Suresi gecmis kayitlarin koordinatlarini bosaltir.
///
/// Tek islemde en fazla [limit] satir: soguk baslatmada devasa bir UPDATE
/// istegi bekletmesin. Kalan satir varsa `remaining` ile bildirilir.
async function purgeCoordinates({ days, limit = 5000 } = {}) {
  const d = Number.isInteger(days) && days >= 1 ? days : retentionDays();
  const cutoff = cutoffIso(d);

  const r = await execute(`
    UPDATE attendance_logs SET
      latitude = NULL,
      longitude = NULL,
      coords_purged_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    WHERE id IN (
      SELECT id FROM attendance_logs
      WHERE coords_purged_at IS NULL AND latitude IS NOT NULL AND occurred_at < ?
      ORDER BY occurred_at
      LIMIT ${Number(limit)}
    )`, cutoff);

  const left = await queryOne(`
    SELECT COUNT(*) AS c FROM attendance_logs
    WHERE coords_purged_at IS NULL AND latitude IS NOT NULL AND occurred_at < ?`, cutoff);

  return {
    purged: r.changes || 0,
    remaining: Number(left.c) || 0,
    retention_days: d,
    cutoff,
  };
}

/// Saklama durumu: kac kayit hala koordinat tutuyor, en eskisi ne zaman.
async function retentionStatus() {
  const days = retentionDays();
  const cutoff = cutoffIso(days);
  const rows = await queryAll(`
    SELECT
      COUNT(*) FILTER (WHERE latitude IS NOT NULL) AS with_coords,
      COUNT(*) FILTER (WHERE coords_purged_at IS NOT NULL) AS purged,
      COUNT(*) FILTER (WHERE latitude IS NOT NULL AND occurred_at < ?) AS overdue,
      MIN(occurred_at) FILTER (WHERE latitude IS NOT NULL) AS oldest_with_coords,
      COUNT(*) AS total
    FROM attendance_logs`, cutoff);
  const r = rows[0] || {};
  return {
    retention_days: days,
    cutoff,
    total_logs: Number(r.total) || 0,
    with_coordinates: Number(r.with_coords) || 0,
    already_purged: Number(r.purged) || 0,
    overdue: Number(r.overdue) || 0,
    oldest_with_coordinates: r.oldest_with_coords || null,
    note: 'Silinen yalnızca ham koordinatlar. Devam kaydı, mesafe özeti ve '
      + 'konum geçerliliği saklanmaya devam eder.',
  };
}

/// Soguk baslatmada firsatci temizlik.
///
/// Ayri bir zamanlanmis is altyapisi yok; sunucu istek basina ayaga kalkiyor.
/// Hata istegi bloklamasin diye yutuluyor: temizlik ertelenebilir bir is.
async function purgeOnStartup() {
  try {
    const status = await retentionStatus();
    if (status.overdue === 0) return { skipped: true };
    // Soguk baslatmayi uzatmamak icin kucuk partide.
    return await purgeCoordinates({ limit: 1000 });
  } catch (e) {
    return { error: e.message };
  }
}

module.exports = {
  DEFAULT_RETENTION_DAYS,
  retentionDays,
  purgeCoordinates,
  retentionStatus,
  purgeOnStartup,
};
