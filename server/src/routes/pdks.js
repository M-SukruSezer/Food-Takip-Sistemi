const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth, requireRole, allowsStore } = require('../auth');
const { logActivity } = require('../utils');
const geo = require('../pdks/geo');
const dev = require('../pdks/device');
const qr = require('../pdks/qr');
const t = require('../pdks/time');
const sheet = require('../pdks/timesheet');

const router = express.Router();

router.use(requireAuth);

// Kiosk kodu gosterebilen ve baskasi adina okutabilen roller.
const KIOSK_ROLES = ['super_admin', 'store_manager', 'shift_supervisor'];

/// Magazayi PDKS icin hazir olup olmadigiyla birlikte getirir.
async function getStore(storeId) {
  return queryOne(
    `SELECT id, name, latitude, longitude, geofence_radius_m, qr_secret, qr_mode,
            pdks_enabled, active
     FROM stores WHERE id = ?`,
    storeId
  );
}

/// Personelin son devam kaydi. "Su an iceride mi" ve tekrar giris kontrolu.
async function lastLog(userId) {
  return queryOne(
    `SELECT id, type, method, occurred_at, work_date, latitude, longitude
     FROM attendance_logs WHERE user_id = ? ORDER BY occurred_at DESC, id DESC LIMIT 1`,
    userId
  );
}

/// Kaydin yazilacagi IS GUNU.
///
/// Gece vardiyasinda cikis ertesi takvim gunune duser. Puantaj work_date'e
/// gore grupladigi icin kayit vardiyanin BASLADIGI gune yazilmali.
///
/// Sira:
///   1. Acik bir giris varsa cikis onun is gunune yazilir (tartisma yok).
///   2. Yerel bugune vardiya atanmissa bugun.
///   3. Dune atanan vardiya gece yarisini geciyor ve daha bitmemisse dun.
///   4. Hicbiri yoksa yerel bugun — plansiz calisma da kayda gecer, puantaj
///      Adim 4'te "vardiya atanmamis" olarak isaretler.
async function resolveWorkDate(userId, atIso, openLog) {
  if (openLog) return openLog.work_date;

  const today = t.localDate(atIso);
  const assignedToday = await queryOne(
    `SELECT us.id FROM user_shifts us
     WHERE us.user_id = ? AND us.work_date = ? AND us.is_day_off = 0 LIMIT 1`,
    userId, today
  );
  if (assignedToday) return today;

  const yesterday = t.shiftDate(today, -1);
  const overnight = await queryAll(
    `SELECT s.start_time, s.end_time FROM user_shifts us
     JOIN shifts s ON s.id = us.shift_id
     WHERE us.user_id = ? AND us.work_date = ? AND us.is_day_off = 0`,
    userId, yesterday
  );
  const nowMinutes = t.localMinutes(atIso);
  for (const s of overnight) {
    if (!t.crossesMidnight(s.start_time, s.end_time)) continue;
    const end = t.parseHhmm(s.end_time);
    // Gece vardiyasi dun basladi, bugun end_time'da bitiyor. Su an bitisten
    // once ya da bitise yakinsa kayit dunun is gunune ait.
    if (end !== null && nowMinutes <= end + 120) return yesterday;
  }
  return today;
}

/// Giris/cikis istegini dogrular ve kayda yazilacak alanlari uretir.
///
/// Iki yontem: QR ve GPS. Baska yontem yok — sema da reddediyor.
async function buildEntry({ req, store, body, atIso }) {
  const method = String(body.method || '').toUpperCase();
  if (method !== 'QR' && method !== 'GPS') {
    return { error: 'Yöntem QR veya GPS olmalıdır' };
  }

  const lat = body.latitude === undefined || body.latitude === null ? null : Number(body.latitude);
  const lon = body.longitude === undefined || body.longitude === null ? null : Number(body.longitude);
  const accuracy = body.accuracy === undefined || body.accuracy === null ? null : Number(body.accuracy);
  // Cihaz bildirmediyse undefined kalir: "bilinmiyor" ile "sahte degil" ayri.
  const isMocked = typeof body.is_mocked === 'boolean' ? body.is_mocked : undefined;

  // Cihaz butunlugu YONTEMDEN BAGIMSIZ degerlendirilir: bayraklar konumu
  // degil cihazi anlatiyor, dolayisiyla gecerli bir QR okutulsa da emulatorden
  // mesai girisi kabul edilmez.
  const integrity = dev.parseIntegrity(body.device_integrity);
  const assessment = dev.assessDevice({ isMocked, integrity });
  if (assessment.blocked) {
    return { error: assessment.reason, flags: assessment.flags };
  }

  const entry = {
    method,
    latitude: null,
    longitude: null,
    accuracy_m: null,
    distance_m: null,
    is_valid_location: null,
    is_mocked: isMocked === undefined ? null : (isMocked ? 1 : 0),
    risk_flags: dev.serializeFlags(assessment.flags),
    qr_token_hash: null,
  };

  if (method === 'GPS') {
    const v = geo.verifyLocation({
      store, latitude: lat, longitude: lon, accuracy, isMocked,
    });
    if (!v.ok) return { error: v.reason, distance: v.distance };
    entry.latitude = lat;
    entry.longitude = lon;
    entry.accuracy_m = accuracy;
    entry.distance_m = v.distance;
    entry.is_valid_location = 1;
    return { entry };
  }

  // QR
  const token = body.qr_token;
  const v = qr.verifyToken(token, store, new Date(atIso).getTime());
  if (!v.ok) return { error: v.reason };
  entry.qr_token_hash = v.tokenHash;

  // Sabit basili kod fotograflanip uzaktan okutulabilir; tek basina yeterli
  // sayilmaz, konum dogrulamasi da istenir. Donen kod ve personel token'i
  // zaten zamana bagli oldugu icin bu zorunluluk yoktur.
  if (v.mode === 'static') {
    const loc = geo.verifyLocation({ store, latitude: lat, longitude: lon, accuracy, isMocked });
    if (!loc.ok) {
      return {
        error: 'Sabit QR kod yalnızca iş yerindeyken geçerlidir. ' + loc.reason,
        distance: loc.distance,
      };
    }
    entry.latitude = lat;
    entry.longitude = lon;
    entry.accuracy_m = accuracy;
    entry.distance_m = loc.distance;
    entry.is_valid_location = 1;
  } else if (geo.isValidCoordinate(lat, lon) && isMocked !== true) {
    // Donen kodda konum zorunlu degil ama gonderildiyse denetim icin yazilir.
    const d = geo.haversineMeters(
      Number(store.latitude), Number(store.longitude), lat, lon
    );
    if (store.latitude !== null && store.longitude !== null) {
      entry.latitude = lat;
      entry.longitude = lon;
      entry.accuracy_m = accuracy;
      entry.distance_m = d;
      entry.is_valid_location = d <= Number(store.geofence_radius_m) + Math.min(accuracy || 0, geo.MAX_ACCURACY_M) ? 1 : 0;
    }
  }
  return { entry, mode: v.mode, tokenUserId: v.userId };
}

/// Giris/cikis kaydini yazar.
async function record({ req, targetUserId, store, type, entry, atIso, workDate, note }) {
  const r = await execute(
    `INSERT INTO attendance_logs
       (user_id, store_id, type, method, occurred_at, work_date,
        latitude, longitude, accuracy_m, distance_m, is_valid_location,
        is_mocked, risk_flags, qr_token_hash, device_label, note, created_by)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) RETURNING id`,
    targetUserId, store.id, type, entry.method, atIso, workDate,
    entry.latitude, entry.longitude, entry.accuracy_m, entry.distance_m,
    entry.is_valid_location, entry.is_mocked, entry.risk_flags, entry.qr_token_hash,
    entry.device_label || null, note || null, req.user.id
  );
  const EYLEM = {
    GIRIS: 'PDKS_GIRIS', CIKIS: 'PDKS_CIKIS',
    MOLA_BASLA: 'PDKS_MOLA_BASLA', MOLA_BITIR: 'PDKS_MOLA_BITIR',
  };
  const ETIKET = {
    GIRIS: 'giriş', CIKIS: 'çıkış',
    MOLA_BASLA: 'mola başlangıcı', MOLA_BITIR: 'mola bitişi',
  };
  await logActivity(req.user, EYLEM[type] || 'PDKS_GIRIS',
    'attendance_log', r.lastInsertRowid,
    `${entry.method} ile ${ETIKET[type] || type}`
    + (entry.distance_m !== null ? ` (${Math.round(entry.distance_m)} m)` : '')
    + (targetUserId !== req.user.id ? ' — kiosk tarafından okutuldu' : '')
    + (entry.risk_flags ? ` — uyarı: ${dev.labelsFor(entry.risk_flags).join(', ')}` : ''),
    store.id);
  return Number(r.lastInsertRowid);
}

/// Ortak giris/cikis akisi.
async function punch(req, res, type) {
  const body = req.body || {};
  const atIso = new Date().toISOString();

  // Kiosk personel token'i okuttuysa kayit o personele yazilir.
  let targetUserId = req.user.id;
  let storeId = req.user.store_id;

  if (body.qr_token) {
    const tokenStoreId = qr.peekStoreId(body.qr_token);
    if (!tokenStoreId) return res.status(400).json({ error: 'QR kod tanınmadı' });
    // Okutan kisi o magazaya erisebiliyor olmali.
    if (!allowsStore(req, tokenStoreId) && tokenStoreId !== req.user.store_id) {
      return res.status(403).json({ error: 'Bu mağazada işlem yapamazsınız' });
    }
    storeId = tokenStoreId;
  }
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });

  const store = await getStore(storeId);
  if (!store) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  if (!store.pdks_enabled) {
    return res.status(400).json({ error: 'Bu mağazada PDKS etkin değil' });
  }

  const built = await buildEntry({ req, store, body, atIso });
  if (built.error) {
    return res.status(400).json({ error: built.error, distance_m: built.distance ?? null });
  }

  // Personel token'i okutulduysa kayit token'daki kisiye yazilir; bunu
  // yalnizca kiosk yetkisi olan roller yapabilir.
  if (built.tokenUserId) {
    if (built.tokenUserId !== req.user.id && !KIOSK_ROLES.includes(req.user.role)) {
      return res.status(403).json({ error: 'Başka personel adına işlem yapamazsınız' });
    }
    targetUserId = built.tokenUserId;
  }

  const target = await queryOne(
    'SELECT id, full_name, store_id, active FROM users WHERE id = ?', targetUserId
  );
  if (!target || !target.active) return res.status(404).json({ error: 'Personel bulunamadı' });
  if (Number(target.store_id) !== Number(store.id)) {
    return res.status(400).json({ error: 'Personel bu mağazaya kayıtlı değil' });
  }

  const last = await lastLog(targetUserId);

  // Mola adimlari. Dort adimli akis:
  //   (yok) -> GIRIS -> [MOLA_BASLA -> MOLA_BITIR]* -> CIKIS
  // Gecersiz siralama burada kesiliyor; puantaj tarafi da eslesmeyen kaydi
  // isaretliyor ama once kaydin hic olusmamasi daha iyi.
  if (type === 'MOLA_BASLA') {
    if (!last || last.type === 'CIKIS') {
      return res.status(400).json({ error: 'Molaya çıkmak için önce işe giriş yapmalısınız' });
    }
    if (last.type === 'MOLA_BASLA') {
      return res.status(400).json({ error: 'Zaten moladasınız. Mola bitişi okutun.' });
    }
  }
  if (type === 'MOLA_BITIR' && (!last || last.type !== 'MOLA_BASLA')) {
    return res.status(400).json({ error: 'Açık bir mola kaydınız yok' });
  }
  // Molada kalmisken cikis: mola suresi bilinmedigi icin puantajda
  // dusulemiyor. Once molayi bitirmesi isteniyor.
  if (type === 'CIKIS' && last && last.type === 'MOLA_BASLA') {
    return res.status(400).json({
      error: 'Moladasınız. Çıkış yapmadan önce mola bitişini okutun.',
    });
  }
  if (type === 'GIRIS' && last && last.type === 'MOLA_BASLA') {
    return res.status(400).json({ error: 'Zaten moladasınız. Mola bitişi okutun.' });
  }

  if (type === 'GIRIS' && last && last.type === 'GIRIS') {
    return res.status(400).json({
      error: 'Açık bir giriş kaydınız var. Önce çıkış yapmalısınız.',
      open_since: last.occurred_at,
    });
  }
  if (type === 'CIKIS' && (!last || last.type === 'CIKIS')) {
    return res.status(400).json({ error: 'Açık bir giriş kaydınız yok' });
  }

  // Konum atlamasi: ayni kisi kisa sure once cok uzakta gorunmusse biri
  // sahtedir. Mock bayragini vermeyen web istemcisinde de calisir.
  if (entryHasCoords(built.entry)) {
    const tp = geo.detectTeleport(last, {
      latitude: built.entry.latitude, longitude: built.entry.longitude, at: atIso,
    });
    if (tp.teleport) {
      return res.status(400).json({ error: `Konum tutarsız: ${tp.reason}` });
    }
  }

  // Mola ve cikis kayitlari ACIK GIRISIN is gunune yazilir. Aksi halde gece
  // vardiyasinda 02:00'de verilen mola ertesi takvim gunune duser ve puantaj
  // o gunun ciftini bolerdi.
  const workDate = await resolveWorkDate(
    targetUserId, atIso, type === 'GIRIS' ? null : last
  );

  let id;
  try {
    id = await record({
      req, targetUserId, store, type, entry: built.entry, atIso, workDate,
      note: body.note,
    });
  } catch (e) {
    // Tekil indeks: ayni personel ayni token'i ikinci kez okutmus.
    if (String(e.message).includes('idx_attendance_qr_token_user')) {
      return res.status(400).json({ error: 'Bu QR kod zaten kullanıldı, yeni kodu okutun' });
    }
    throw e;
  }

  res.status(201).json({
    id,
    type,
    method: built.entry.method,
    occurred_at: atIso,
    work_date: workDate,
    distance_m: built.entry.distance_m,
    user: { id: target.id, full_name: target.full_name },
    store: { id: store.id, name: store.name },
  });
}

function entryHasCoords(entry) {
  return entry.latitude !== null && entry.longitude !== null;
}

router.post('/check-in', (req, res) => punch(req, res, 'GIRIS'));
router.post('/check-out', (req, res) => punch(req, res, 'CIKIS'));
// Mola adimlari isin AYNI dogrulamasindan geciyor (QR ya da GPS): molaya
// cikan personel de is yerinde olmali ve mola disindan okutamamali.
router.post('/break-start', (req, res) => punch(req, res, 'MOLA_BASLA'));
router.post('/break-end', (req, res) => punch(req, res, 'MOLA_BITIR'));

/// Personelin kendi durumu: iceride mi, bugunun vardiyasi, bugunun kayitlari.
router.get('/me', async (req, res) => {
  const storeId = req.user.store_id;
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });
  const store = await getStore(storeId);
  const today = t.localDate();
  const last = await lastLog(req.user.id);

  const shifts = await queryAll(
    `SELECT s.id, s.name, s.start_time, s.end_time, s.break_duration_minutes,
            s.late_tolerance_minutes, us.is_day_off
     FROM user_shifts us LEFT JOIN shifts s ON s.id = us.shift_id
     WHERE us.user_id = ? AND us.work_date = ? ORDER BY s.start_time`,
    req.user.id, today
  );
  // Acik kayit varsa ONUN is gunu gosterilir: gece vardiyasinda acik giris
  // dunun is gunune yazili oldugu icin bugunun kayitlarini sormak listeyi bos
  // birakiyordu.
  const acik = last && last.type !== 'CIKIS' ? last.work_date : today;
  const logs = await queryAll(
    `SELECT id, type, method, occurred_at, distance_m, is_valid_location
     FROM attendance_logs WHERE user_id = ? AND work_date = ?
     ORDER BY occurred_at`,
    req.user.id, acik
  );

  // Dort adimli akista bir sonraki gecerli adim. Arayuz dugmeleri buna gore
  // ciziliyor; kurali istemcide tekrar yazmak ikisinin ayrismasi demekti.
  const durum = !last || last.type === 'CIKIS' ? 'DISARIDA'
    : last.type === 'MOLA_BASLA' ? 'MOLADA' : 'ICERIDE';

  res.json({
    work_date: acik,
    state: durum,
    // Molada olan personel de ICERIDE sayilir: mesai devam ediyor.
    is_inside: durum !== 'DISARIDA',
    on_break: durum === 'MOLADA',
    open_since: durum !== 'DISARIDA'
      ? (logs.find((l) => l.type === 'GIRIS') || {}).occurred_at ?? last.occurred_at
      : null,
    break_since: durum === 'MOLADA' ? last.occurred_at : null,
    // Bu is gununde biriken mola suresi (dakika); acik mola sayilmaz.
    break_minutes_today: sheet.recordedBreakMinutes(sheet.pairLogs(logs).breaks),
    // Izin verilen sonraki adimlar.
    can: {
      check_in: durum === 'DISARIDA',
      check_out: durum === 'ICERIDE',
      break_start: durum === 'ICERIDE',
      break_end: durum === 'MOLADA',
    },
    store: store && {
      id: store.id, name: store.name, pdks_enabled: !!store.pdks_enabled,
      qr_mode: store.qr_mode,
      // Koordinat istemciye gonderilir: uygulama mesafeyi kendi gosterebilsin.
      // Sir GONDERILMEZ.
      latitude: store.latitude, longitude: store.longitude,
      geofence_radius_m: store.geofence_radius_m,
      has_location: store.latitude !== null && store.longitude !== null,
    },
    shifts: shifts.map((s) => ({
      ...s, is_day_off: !!s.is_day_off,
    })),
    logs,
  });
});

/// Personelin kioskta okutacagi kisisel QR kodu.
router.get('/me/qr', async (req, res) => {
  const storeId = req.user.store_id;
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });
  const store = await getStore(storeId);
  if (!store || !store.pdks_enabled) {
    return res.status(400).json({ error: 'Bu mağazada PDKS etkin değil' });
  }
  if (!store.qr_secret) {
    return res.status(400).json({ error: 'Bu mağazada QR ile giriş tanımlı değil' });
  }
  res.json(qr.issueUserToken(store, req.user.id));
});

/// Kioskta gosterilecek magaza QR kodu.
router.get('/qr/current', requireRole(...KIOSK_ROLES), async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (!storeId) return res.status(400).json({ error: 'Mağaza belirtilmeli' });
  if (!allowsStore(req, storeId)) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }
  const store = await getStore(storeId);
  if (!store) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  if (!store.pdks_enabled) return res.status(400).json({ error: 'Bu mağazada PDKS etkin değil' });
  if (!store.qr_secret) return res.status(400).json({ error: 'Bu mağazada QR ile giriş tanımlı değil' });

  if (store.qr_mode === 'static') {
    return res.json({ mode: 'static', ...qr.issueStaticToken(store) });
  }
  res.json({ mode: 'rotating', ...qr.issueRotatingToken(store) });
});

module.exports = router;
module.exports.KIOSK_ROLES = KIOSK_ROLES;
// Gece vardiyasinda kaydin hangi is gunune yazilacagi bu adimin en ince
// mantigi; duvar saatinden bagimsiz test edilebilmesi icin disa aciliyor.
module.exports.resolveWorkDate = resolveWorkDate;

// ---- Calisan bildirimleri ----

/// Kendi bildirimlerim.
///
/// Yalnizca KENDI kayitlari: user_id sabit req.user.id, sorgu parametresiyle
/// baskasinin bildirimleri istenemiyor.
router.get('/notifications', async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 30, 100);
  const rows = await queryAll(
    `SELECT id, kind, title, body, data, read_at, created_at
     FROM notifications WHERE user_id = ?
     ORDER BY created_at DESC, id DESC LIMIT ?`, req.user.id, limit);
  const unread = await queryOne(
    'SELECT COUNT(*) AS c FROM notifications WHERE user_id = ? AND read_at IS NULL',
    req.user.id);
  res.json({
    unread: Number(unread.c),
    items: rows.map((r) => ({
      ...r,
      data: r.data ? JSON.parse(r.data) : null,
      read: r.read_at != null,
    })),
  });
});

/// Bildirimi okundu isaretle.
router.post('/notifications/:id/read', async (req, res) => {
  const r = await execute(
    `UPDATE notifications SET read_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
     WHERE id = ? AND user_id = ? AND read_at IS NULL`,
    Number(req.params.id), req.user.id);
  // Baskasinin bildirimi bulunamamis gibi davraniyor: kimlik sizmasin.
  if (!r.changes) return res.status(404).json({ error: 'Bildirim bulunamadı' });
  res.json({ ok: true });
});

/// Tumunu okundu isaretle.
router.post('/notifications/read-all', async (req, res) => {
  const r = await execute(
    `UPDATE notifications SET read_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
     WHERE user_id = ? AND read_at IS NULL`, req.user.id);
  res.json({ ok: true, marked: r.changes });
});
