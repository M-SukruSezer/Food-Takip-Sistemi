const express = require('express');
const { queryAll, queryOne, execute, transaction } = require('../db');
const {
  requireAuth, requireRole, resolveStoreScope, storeFilter, allowsStore, MANAGER_ROLES,
  NON_PERSONNEL_ROLES, personnelOnly,
} = require('../auth');
const { logActivity } = require('../utils');
const bal = require('../pdks/balance');
const t = require('../pdks/time');
const notify = require('../pdks/notify');
const roster = require('../pdks/rosterChanges');

const router = express.Router();

router.use(requireAuth);

const requireManager = requireRole(...MANAGER_ROLES);

/// Bildirim metinlerinde kullanilan tur adi.
const TUR_ADI = {
  IZIN: 'Yıllık izin',
  SAATLIK_IZIN: 'Saatlik izin',
  VARDIYA_TAKAS: 'Vardiya takas talebi',
  VARDIYA_DEVIR: 'Vardiya devir talebi',
  HAFTALIK_OFF: 'Haftalık OFF talebi',
  RAPOR: 'Rapor bildirimi',
};
const turAdi = (tip) => TUR_ADI[tip] || tip;

/// Talebin tek satirlik ozeti.
function talepOzet(row) {
  if (row.type === 'IZIN') {
    return `${row.start_at} – ${row.end_at}, ${row.days} gün`;
  }
  if (row.type === 'SAATLIK_IZIN') return `${row.hours} saat`;
  if (row.type === 'VARDIYA_TAKAS') {
    return row.target_shift_date && row.target_shift_date !== row.shift_date
      ? `${row.shift_date} ↔ ${row.target_shift_date} vardiyaları`
      : `${row.shift_date} tarihli vardiya`;
  }
  if (row.type === 'VARDIYA_DEVIR') return `${row.shift_date} tarihli vardiya`;
  if (row.type === 'HAFTALIK_OFF') {
    return row.target_shift_date
      ? `OFF günü ${row.target_shift_date} → ${row.shift_date}`
      : `${row.shift_date} OFF günü`;
  }
  if (row.type === 'RAPOR') {
    return row.start_at === row.end_at
      ? `${row.start_at}, 1 gün`
      : `${row.start_at} – ${row.end_at}, ${row.days} gün`;
  }
  return '';
}

/// Talebi karara baglayacak yoneticiler.
///
/// Yalnizca MANAGER_ROLES: IK bu talepleri karara baglayamadigi icin
/// (hrAllows yalnizca puantaj goruntulemeye izin veriyor) bildirim de almiyor
/// — uzerine islem yapamayacagi bildirim gurultudur.
///
/// Magaza kapsami: magazaya bagli yonetici yalnizca KENDI magazasinin
/// talebini gorur; magazasi olmayan ust roller (super_admin,
/// operations_manager, regional_manager) hepsini gorur.
///
/// Talebi ACAN kisi listeye GIRMEZ: kendi talebini zaten onaylayamiyor.
const UST_ROLLER = ['super_admin', 'operations_manager', 'regional_manager'];
async function kararVericiler(storeId, haricUserId) {
  const ph = MANAGER_ROLES.map(() => '?').join(',');
  const ust = UST_ROLLER.map(() => '?').join(',');
  const rows = await queryAll(
    `SELECT id FROM users
     WHERE active = 1 AND role IN (${ph})
       AND (store_id = ? OR role IN (${ust}))
       AND id <> ?`,
    ...MANAGER_ROLES, storeId, ...UST_ROLLER, haricUserId);
  return rows.map((r) => Number(r.id));
}
const TYPES = ['IZIN', 'SAATLIK_IZIN', 'VARDIYA_TAKAS', 'VARDIYA_DEVIR', 'HAFTALIK_OFF', 'RAPOR'];
const SHIFT_TYPES = ['VARDIYA_TAKAS', 'VARDIYA_DEVIR'];
/// Onayla birlikte haftalik cizelgeyi degistiren turler.
const ROSTER_TYPES = [...SHIFT_TYPES, 'HAFTALIK_OFF', 'RAPOR'];

/// Rapor gorseli: kameradan ya da galeriden, istemcide kucultulmus veri URL'si.
const RAPOR_GORSEL = /^data:image\/(png|jpe?g|webp);base64,[A-Za-z0-9+/=]+$/;
const RAPOR_GORSEL_MAX = 3 * 1024 * 1024;
const RAPOR_MAX_GUN = 31;
const TARIH = /^\d{4}-\d{2}-\d{2}$/;

/// Liste sorgusunda rapor gorseli TASINMAZ (satir basina megabaytlar);
/// yalnizca var olup olmadigi doner, gorsel ayri uctan istenir.
const LISTE_KOLONLARI = `r.id, r.user_id, r.store_id, r.type, r.start_at, r.end_at, r.days,
  r.hours, r.amount, r.reason, r.status, r.manager_id, r.decided_at, r.decision_note,
  r.created_at, r.target_user_id, r.shift_date, r.target_confirmed_at, r.target_shift_date,
  (r.attachment IS NOT NULL) AS has_attachment`;

/// Bir tarih araligindaki resmi tatiller.
///
/// Magazaya ozel tatil genel takvimi gecersiz kilabilir; holidayMap bu onceligi
/// uyguluyor.
async function holidaysFor(storeId, from, to) {
  const rows = await queryAll(`
    SELECT holiday_date, name, is_half_day, store_id FROM public_holidays
    WHERE holiday_date >= ? AND holiday_date <= ?
      AND (store_id IS NULL OR store_id = ?)`, from, to, storeId);
  return bal.holidayMap(rows);
}

/// Personelin profili; kayit yoksa varsayilanlar.
async function profileOf(userId) {
  const p = await queryOne('SELECT * FROM pdks_profiles WHERE user_id = ?', userId);
  return {
    hired_at: p?.hired_at ?? null,
    annual_leave_days: p ? Number(p.annual_leave_days) : 14,
    weekly_off_days: bal.parseWeeklyOff(p?.weekly_off_days),
  };
}

/// Bakiye: hak, kullanilan, bekleyen, kalan.
///
/// BEKLEYEN talep de dusulur; aksi halde personel ust uste talep gonderip
/// hakkindan fazlasini onaya dusurebilir.
async function balancesOf(userId, atIso = new Date().toISOString()) {
  const profile = await profileOf(userId);
  const year = bal.leaveYearRange(profile.hired_at, atIso);
  const month = bal.monthRange(atIso);

  // Izin yili icinde kalan gunler. start_at araliga giren talepler sayilir.
  const leave = await queryOne(`
    SELECT
      COALESCE(SUM(CASE WHEN status='APPROVED' THEN days ELSE 0 END),0) AS used,
      COALESCE(SUM(CASE WHEN status='PENDING'  THEN days ELSE 0 END),0) AS pending
    FROM personnel_requests
    WHERE user_id = ? AND type = 'IZIN' AND status <> 'REJECTED' AND status <> 'CANCELLED'
      AND start_at >= ? AND start_at <= ?`, userId, year.from, year.to);

  const hourly = await queryOne(`
    SELECT
      COALESCE(SUM(CASE WHEN status='APPROVED' THEN hours ELSE 0 END),0) AS used,
      COALESCE(SUM(CASE WHEN status='PENDING'  THEN hours ELSE 0 END),0) AS pending
    FROM personnel_requests
    WHERE user_id = ? AND type = 'SAATLIK_IZIN' AND status IN ('APPROVED','PENDING')
      AND substr(start_at, 1, 10) >= ? AND substr(start_at, 1, 10) <= ?`,
    userId, month.from, month.to);

  const summary = bal.summarize({
    entitlementDays: profile.annual_leave_days,
    usedDays: Number(leave.used) || 0,
    pendingDays: Number(leave.pending) || 0,
    usedHours: Number(hourly.used) || 0,
    pendingHours: Number(hourly.pending) || 0,
  });
  return {
    ...summary,
    leave_year: year,
    month,
    weekly_off_days: profile.weekly_off_days,
    hired_at: profile.hired_at,
    notes: [
      'Yıllık izin hesabında hafta tatili ve resmi tatil günleri düşülür; '
        + 'arife gibi yarım tatiller 0,5 gün sayılır.',
      'Dini bayram tarihleri her yıl kaydığı için yöneticinin tatil '
        + 'takvimine eklemesi gerekir.',
    ],
  };
}

/// Vardiya takas/devir talebinde secilecek personel listesi. Herkes kendi
/// magazasindaki aktif meslektaslarini gorebilir (isim + id disinda bilgi yok).
router.get('/requests/colleagues', async (req, res) => {
  const storeId = req.user.store_id;
  if (!storeId) return res.json([]);
  const rows = await queryAll(`
    SELECT id, full_name FROM users
    WHERE store_id = ? AND active = 1 AND id <> ? ${personnelOnly('')}
    ORDER BY full_name`, storeId, req.user.id);
  res.json(rows);
});

router.get('/requests/balances', async (req, res) => {
  const userId = req.query.userId ? Number(req.query.userId) : req.user.id;
  if (userId !== req.user.id) {
    if (!MANAGER_ROLES.includes(req.user.role)) {
      return res.status(403).json({ error: 'Başka personelin bakiyesini göremezsiniz' });
    }
    const u = await queryOne('SELECT store_id FROM users WHERE id = ?', userId);
    if (!u) return res.status(404).json({ error: 'Personel bulunamadı' });
    if (!allowsStore(req, u.store_id)) {
      return res.status(403).json({ error: 'Bu personele erişim yetkiniz yok' });
    }
  }
  res.json(await balancesOf(userId));
});

/// Talep listesi. Personel kendi taleplerini, yonetici magazasinin taleplerini.
router.get('/requests', async (req, res) => {
  const isManager = MANAGER_ROLES.includes(req.user.role);
  const params = [];
  let where = '1 = 1';

  if (!isManager) {
    // Takas talebinde hedef taraf da kendi listesinde gormeli (onaylayabilsin).
    where += ' AND (r.user_id = ? OR r.target_user_id = ?)';
    params.push(req.user.id, req.user.id);
  } else {
    const scope = resolveStoreScope(req, res);
    if (!scope.ok) return undefined;
    const f = storeFilter(scope, 'r.store_id');
    where += f.sql;
    params.push(...f.params);
    if (req.query.userId) { where += ' AND r.user_id = ?'; params.push(Number(req.query.userId)); }
  }
  if (req.query.status) {
    const st = String(req.query.status).toUpperCase();
    if (!['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'].includes(st)) {
      return res.status(400).json({ error: 'Geçersiz durum' });
    }
    where += ' AND r.status = ?';
    params.push(st);
  }
  if (req.query.type) {
    const ty = String(req.query.type).toUpperCase();
    if (!TYPES.includes(ty)) return res.status(400).json({ error: 'Geçersiz talep türü' });
    where += ' AND r.type = ?';
    params.push(ty);
  }

  const rows = await queryAll(`
    SELECT ${LISTE_KOLONLARI}, u.full_name, m.full_name AS manager_name, s.name AS store_name,
      tu.full_name AS target_name
    FROM personnel_requests r
    JOIN users u ON u.id = r.user_id
    LEFT JOIN users m ON m.id = r.manager_id
    LEFT JOIN stores s ON s.id = r.store_id
    LEFT JOIN users tu ON tu.id = r.target_user_id
    WHERE ${where}
    ORDER BY CASE WHEN r.status = 'PENDING' THEN 0 ELSE 1 END, r.created_at DESC
    LIMIT 500`, ...params);
  res.json(rows);
});

/// Talep olustur.
router.post('/requests', async (req, res) => {
  const body = req.body || {};
  const type = String(body.type || '').toUpperCase();
  if (!TYPES.includes(type)) {
    return res.status(400).json({ error: 'Geçersiz talep türü' });
  }
  const storeId = req.user.store_id;
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });
  const reason = String(body.reason || '').trim();
  if (reason.length > 500) return res.status(400).json({ error: 'Gerekçe en fazla 500 karakter' });

  // amount kolonu semada duruyor (eski kayitlar icin) ama artik hep null.
  const fields = {
    start_at: null, end_at: null, days: null, hours: null, amount: null,
    target_user_id: null, shift_date: null, target_shift_date: null,
  };

  /// Karar vericilere (ve takasta karsi tarafa) haber verip 201 doner.
  async function bildirVeDon(id, extra = {}) {
    const detail = talepOzet({ type, ...fields });
    const alicilar = await kararVericiler(storeId, req.user.id);
    // Takasta karsi tarafa da haber verilir; onayi o baslatir.
    if (type === 'VARDIYA_TAKAS') alicilar.push(fields.target_user_id);
    for (const aliciId of alicilar) {
      await notify.requestCreated({
        managerId: aliciId,
        requesterName: req.user.full_name,
        typeLabel: turAdi(type),
        detail,
        requestId: id,
      });
    }
    await logActivity(req.user, 'TALEP_OLUSTUR', 'personnel_request', id,
      `${type}: ${detail}`, storeId);
    return res.status(201).json({ id, ...fields, ...extra, type, status: 'PENDING' });
  }

  const bugun = t.localDate();

  if (SHIFT_TYPES.includes(type)) {
    if (!reason) return res.status(400).json({ error: 'Gerekçe zorunludur' });
    const shiftDate = String(body.shift_date || '');
    if (!TARIH.test(shiftDate)) {
      return res.status(400).json({ error: 'Vardiya tarihi YYYY-AA-GG biçiminde olmalıdır' });
    }
    if (shiftDate < bugun) {
      return res.status(400).json({ error: 'Geçmiş tarihli vardiya için talep oluşturulamaz' });
    }
    if (!await roster.vardiyasiVar(req.user.id, shiftDate)) {
      return res.status(400).json({ error: 'Bu tarihte size ait bir vardiya bulunamadı' });
    }
    const openRequest = await queryOne(`
      SELECT id FROM personnel_requests
      WHERE user_id = ? AND shift_date = ? AND status = 'PENDING' AND type IN ('VARDIYA_TAKAS','VARDIYA_DEVIR')
      LIMIT 1`, req.user.id, shiftDate);
    if (openRequest) {
      return res.status(400).json({ error: 'Bu vardiya için zaten bekleyen bir talebiniz var' });
    }
    fields.shift_date = shiftDate;

    if (type === 'VARDIYA_TAKAS') {
      const targetId = Number(body.target_user_id);
      if (!targetId) return res.status(400).json({ error: 'Takas için bir personel seçmelisiniz' });
      if (targetId === req.user.id) {
        return res.status(400).json({ error: 'Kendinizle takas talebi oluşturamazsınız' });
      }
      const target = await queryOne(
        'SELECT id, active, role, store_id FROM users WHERE id = ?', targetId);
      if (!target || !target.active || Number(target.store_id) !== Number(storeId)
        || NON_PERSONNEL_ROLES.includes(target.role)) {
        return res.status(400).json({ error: 'Geçersiz hedef personel' });
      }
      fields.target_user_id = targetId;
      // Karsi tarafin vardiyasi baska gundeyse (Pazartesi benim, Sali onun)
      // iki gun de takasa girer; ayni gunse o gunun vardiyalari degisir.
      const targetDate = body.target_shift_date ? String(body.target_shift_date) : shiftDate;
      if (!TARIH.test(targetDate) || targetDate < bugun) {
        return res.status(400).json({ error: 'Karşı tarafın vardiya tarihi geçersiz' });
      }
      if (targetDate !== shiftDate) {
        if (!await roster.vardiyasiVar(targetId, targetDate)) {
          return res.status(400).json({
            error: 'Seçtiğiniz personelin bu tarihte bir vardiyası bulunamadı',
          });
        }
        fields.target_shift_date = targetDate;
      }
    }

    const r = await execute(`
      INSERT INTO personnel_requests
        (user_id, store_id, type, target_user_id, shift_date, target_shift_date, reason)
      VALUES (?,?,?,?,?,?,?) RETURNING id`,
      req.user.id, storeId, type, fields.target_user_id, fields.shift_date,
      fields.target_shift_date, reason);
    return bildirVeDon(Number(r.lastInsertRowid));
  }

  if (type === 'HAFTALIK_OFF') {
    const offDate = String(body.shift_date || '');
    if (!TARIH.test(offDate)) {
      return res.status(400).json({ error: 'OFF günü YYYY-AA-GG biçiminde olmalıdır' });
    }
    if (offDate < bugun) {
      return res.status(400).json({ error: 'Geçmiş bir gün için OFF talebi oluşturulamaz' });
    }
    const satirlar = await roster.gunSatirlari(req.user.id, offDate);
    if (satirlar.some((s) => Number(s.is_day_off) === 1)) {
      return res.status(400).json({ error: 'Bu gün zaten OFF gününüz' });
    }
    // Istege bagli: ayni haftadaki mevcut OFF gunu. Verilirse iki gun yer
    // degistirir, haftalik OFF sayisi degismez.
    if (body.target_shift_date) {
      const eskiOff = String(body.target_shift_date);
      if (!TARIH.test(eskiOff) || eskiOff === offDate) {
        return res.status(400).json({ error: 'Değiştirilecek OFF günü geçersiz' });
      }
      if (roster.haftaBasi(eskiOff) !== roster.haftaBasi(offDate)) {
        return res.status(400).json({ error: 'OFF günü yalnızca aynı hafta içinde değiştirilebilir' });
      }
      if (eskiOff < bugun) {
        return res.status(400).json({ error: 'Geçmiş bir OFF günü değiştirilemez' });
      }
      const eski = await roster.gunSatirlari(req.user.id, eskiOff);
      if (!eski.some((s) => Number(s.is_day_off) === 1)) {
        return res.status(400).json({ error: 'Seçtiğiniz gün çizelgede OFF olarak görünmüyor' });
      }
      fields.target_shift_date = eskiOff;
    }
    const acik = await queryOne(`
      SELECT id FROM personnel_requests
      WHERE user_id = ? AND type = 'HAFTALIK_OFF' AND status = 'PENDING'
        AND (shift_date IN (?, ?) OR target_shift_date IN (?, ?)) LIMIT 1`,
    req.user.id, offDate, fields.target_shift_date || offDate,
    offDate, fields.target_shift_date || offDate);
    if (acik) return res.status(400).json({ error: 'Bu gün için zaten bekleyen bir OFF talebiniz var' });
    fields.shift_date = offDate;

    const r = await execute(`
      INSERT INTO personnel_requests
        (user_id, store_id, type, shift_date, target_shift_date, reason)
      VALUES (?,?,?,?,?,?) RETURNING id`,
      req.user.id, storeId, type, fields.shift_date, fields.target_shift_date,
      reason || 'Haftalık OFF günü talebi');
    return bildirVeDon(Number(r.lastInsertRowid));
  }

  if (type === 'RAPOR') {
    const from = String(body.start_at || '');
    const to = String(body.end_at || from);
    if (!TARIH.test(from) || !TARIH.test(to)) {
      return res.status(400).json({ error: 'Rapor tarihleri YYYY-AA-GG biçiminde olmalıdır' });
    }
    if (to < from) return res.status(400).json({ error: 'Bitiş tarihi başlangıçtan önce olamaz' });
    const gunSayisi = roster.gunler(from, to).length;
    if (gunSayisi === 0 || gunSayisi > RAPOR_MAX_GUN) {
      return res.status(400).json({ error: `Rapor en fazla ${RAPOR_MAX_GUN} gün olabilir` });
    }
    const enEski = t.localDate(new Date(Date.now() - 30 * 864e5).toISOString());
    if (from < enEski) {
      return res.status(400).json({ error: 'Rapor başlangıcı en fazla 30 gün öncesi olabilir' });
    }
    const gorsel = body.attachment;
    if (typeof gorsel !== 'string' || !gorsel) {
      return res.status(400).json({ error: 'Rapor görseli zorunludur' });
    }
    if (!RAPOR_GORSEL.test(gorsel)) {
      return res.status(400).json({ error: 'Geçersiz görsel biçimi. PNG, JPEG veya WEBP olmalıdır.' });
    }
    if (gorsel.length > RAPOR_GORSEL_MAX) {
      return res.status(400).json({ error: 'Görsel çok büyük. Lütfen daha küçük bir fotoğraf seçin.' });
    }
    const clash = await queryOne(`
      SELECT id, start_at, end_at FROM personnel_requests
      WHERE user_id = ? AND type = 'RAPOR' AND status IN ('PENDING','APPROVED')
        AND start_at <= ? AND end_at >= ? LIMIT 1`, req.user.id, to, from);
    if (clash) {
      return res.status(400).json({
        error: `${clash.start_at} - ${clash.end_at} tarihlerinde zaten bir rapor kaydınız var`,
      });
    }
    fields.start_at = from;
    fields.end_at = to;
    fields.days = gunSayisi;

    const r = await execute(`
      INSERT INTO personnel_requests
        (user_id, store_id, type, start_at, end_at, days, attachment, reason)
      VALUES (?,?,?,?,?,?,?,?) RETURNING id`,
      req.user.id, storeId, type, from, to, gunSayisi, gorsel, reason || 'Rahatsızlık raporu');
    return bildirVeDon(Number(r.lastInsertRowid), { has_attachment: true });
  }

  if (!reason) return res.status(400).json({ error: 'Gerekçe zorunludur' });

  const balances = await balancesOf(req.user.id);
  const profile = await profileOf(req.user.id);

  if (type === 'IZIN') {
    const from = String(body.start_at || '');
    const to = String(body.end_at || '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) {
      return res.status(400).json({ error: 'İzin tarihleri YYYY-AA-GG biçiminde olmalıdır' });
    }
    if (to < from) return res.status(400).json({ error: 'Bitiş tarihi başlangıçtan önce olamaz' });
    // Resmi tatil ve hafta tatili gunleri izin hakkindan dusulmez.
    const holidays = await holidaysFor(storeId, from, to);
    const days = bal.countLeaveDays(from, to, profile.weekly_off_days, holidays);
    if (days === null) return res.status(400).json({ error: 'Tarih aralığı geçersiz' });
    if (days === 0) {
      return res.status(400).json({
        error: 'Seçilen aralıkta çalışma günü yok (hepsi hafta tatili veya resmi tatil)',
      });
    }
    if (days > balances.leave.remaining_days) {
      return res.status(400).json({
        error: `${days} gün izin talep ettiniz, kalan hakkınız `
          + `${balances.leave.remaining_days} gün`,
      });
    }
    // Ayni gunlere ikinci talep: cift dusum ve cakisan plan olusur.
    const clash = await queryOne(`
      SELECT id, start_at, end_at, status FROM personnel_requests
      WHERE user_id = ? AND type = 'IZIN' AND status IN ('PENDING','APPROVED')
        AND start_at <= ? AND end_at >= ? LIMIT 1`, req.user.id, to, from);
    if (clash) {
      return res.status(400).json({
        error: `${clash.start_at} - ${clash.end_at} tarihlerinde zaten bir izin talebiniz var`,
      });
    }
    fields.start_at = from;
    fields.end_at = to;
    fields.days = days;
  } else {
    // SAATLIK_IZIN
    const from = String(body.start_at || '');
    const to = String(body.end_at || '');
    const hours = bal.countLeaveHours(from, to);
    if (hours === null) {
      return res.status(400).json({
        error: 'Saatlik izin geçerli bir aralık olmalı ve 12 saati geçmemelidir',
      });
    }
    if (t.localDate(from) !== t.localDate(to)) {
      return res.status(400).json({ error: 'Saatlik izin aynı gün içinde olmalıdır' });
    }
    const clash = await queryOne(`
      SELECT id FROM personnel_requests
      WHERE user_id = ? AND type = 'SAATLIK_IZIN' AND status IN ('PENDING','APPROVED')
        AND start_at < ? AND end_at > ? LIMIT 1`, req.user.id, to, from);
    if (clash) return res.status(400).json({ error: 'Bu saatlerde zaten bir talebiniz var' });
    fields.start_at = from;
    fields.end_at = to;
    fields.hours = hours;
  }

  const r = await execute(`
    INSERT INTO personnel_requests
      (user_id, store_id, type, start_at, end_at, days, hours, amount, reason)
    VALUES (?,?,?,?,?,?,?,?,?) RETURNING id`,
    req.user.id, storeId, type, fields.start_at, fields.end_at,
    fields.days, fields.hours, fields.amount, reason);

  // Karar verecek yoneticilere haber. Bildirim YAN ETKI: patlasa da talep
  // olusturulmus sayilir (notify.publish hatalari yutuyor).
  for (const yoneticiId of await kararVericiler(storeId, req.user.id)) {
    await notify.requestCreated({
      managerId: yoneticiId,
      requesterName: req.user.full_name,
      typeLabel: turAdi(type),
      detail: talepOzet({ type, ...fields }),
      requestId: Number(r.lastInsertRowid),
    });
  }

  await logActivity(req.user, 'TALEP_OLUSTUR', 'personnel_request', r.lastInsertRowid,
    `${type}: ` + (type === 'IZIN'
      ? `${fields.start_at} - ${fields.end_at} (${fields.days} gün)`
      : `${fields.hours} saat`), storeId);

  res.status(201).json({ id: Number(r.lastInsertRowid), ...fields, type, status: 'PENDING' });
});

/// Onaylanan talebin haftalik cizelgeye yansimasi (transaction icinde).
async function cizelgeyeYansit(client, row, assignedTargetId, managerId) {
  const kayip = (msg) => Object.assign(new Error('roster-changed'), { userMessage: msg });
  const vardiyasiVar = async (userId, date) => !!(await queryOne(`
    SELECT id FROM user_shifts
    WHERE user_id = ? AND work_date = ? AND shift_id IS NOT NULL LIMIT 1`,
  userId, date, client));

  if (row.type === 'VARDIYA_DEVIR') {
    const shift = await queryOne(`
      SELECT id FROM user_shifts
      WHERE user_id = ? AND work_date = ? AND shift_id IS NOT NULL`,
    row.user_id, row.shift_date, client);
    if (!shift) throw kayip('Bu vardiya artık çizelgede bulunmuyor; talep onaylanamadı');
    await execute('UPDATE user_shifts SET user_id = ? WHERE id = ?',
      [assignedTargetId, shift.id], client);
    return;
  }
  if (row.type === 'VARDIYA_TAKAS') {
    // Talepten bu yana cizelge degistiyse takasin anlami kalmamis olabilir.
    if (!await vardiyasiVar(row.user_id, row.shift_date)) {
      throw kayip('Talep eden personelin vardiyası artık çizelgede yok; talep onaylanamadı');
    }
    if (row.target_shift_date && !await vardiyasiVar(row.target_user_id, row.target_shift_date)) {
      throw kayip('Karşı tarafın vardiyası artık çizelgede yok; talep onaylanamadı');
    }
    await roster.vardiyaTakas(client, {
      aId: Number(row.user_id),
      bId: Number(row.target_user_id),
      dates: [row.shift_date, row.target_shift_date || row.shift_date],
    });
    return;
  }
  if (row.type === 'HAFTALIK_OFF') {
    if (row.target_shift_date) {
      const eski = await queryOne(`
        SELECT id FROM user_shifts
        WHERE user_id = ? AND work_date = ? AND is_day_off = 1`,
      row.user_id, row.target_shift_date, client);
      if (!eski) throw kayip('Değiştirilecek OFF günü artık çizelgede yok; talep onaylanamadı');
    }
    await roster.haftalikOff(client, {
      userId: Number(row.user_id),
      offDate: row.shift_date,
      swapDate: row.target_shift_date || null,
      assignedBy: managerId,
    });
    return;
  }
  if (row.type === 'RAPOR') {
    await roster.raporIsle(client, {
      userId: Number(row.user_id), from: row.start_at, to: row.end_at, assignedBy: managerId,
    });
  }
}

/// Onay / ret. Karar verilmis talep tekrar karara acilmaz.
async function decide(req, res, next) {
  const approve = next === 'APPROVED';
  const row = await queryOne('SELECT * FROM personnel_requests WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Talep bulunamadı' });
  if (!allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu talebe erişim yetkiniz yok' });
  }
  if (row.status !== 'PENDING') {
    return res.status(400).json({
      error: row.status === 'APPROVED' ? 'Bu talep zaten onaylanmış'
        : row.status === 'REJECTED' ? 'Bu talep zaten reddedilmiş'
        : 'Bu talep iptal edilmiş',
    });
  }
  // Kendi talebini onaylamak yetki ayrimini anlamsiz kilar.
  if (Number(row.user_id) === Number(req.user.id)) {
    return res.status(400).json({ error: 'Kendi talebinizi onaylayamazsınız' });
  }

  const note = req.body && req.body.note !== undefined
    ? String(req.body.note).trim() || null : null;
  if (!approve && !note) return res.status(400).json({ error: 'Ret gerekçesi zorunludur' });

  // Talep olusturulduktan sonra hak degismis olabilir (yonetici izin gununu
  // dusurmus ya da baska talep onaylanmis olabilir). Onay aninda tekrar bakilir.
  let assignedTargetId = row.target_user_id ? Number(row.target_user_id) : null;
  if (approve) {
    const b = await balancesOf(row.user_id);
    if (row.type === 'IZIN') {
      // Bu talebin kendi bekleyen gunu zaten dusulmus; geri eklenip
      // karsilastirilir, aksi halde kendi kendini engeller.
      const available = b.leave.remaining_days + Number(row.days || 0);
      if (Number(row.days) > available) {
        return res.status(400).json({
          error: `Onaylanamaz: personelin kalan izin hakkı ${available} gün, `
            + `talep ${row.days} gün`,
        });
      }
    }
    if (row.type === 'VARDIYA_TAKAS' && !row.target_confirmed_at) {
      return res.status(400).json({
        error: 'Karşı taraf henüz onay vermedi; önce personelin mobil onayı bekleniyor',
      });
    }
    if (row.type === 'VARDIYA_DEVIR' && !assignedTargetId) {
      assignedTargetId = Number(req.body && req.body.target_user_id);
      if (!assignedTargetId) {
        return res.status(400).json({ error: 'Devir için bir personel atamalısınız' });
      }
      const target = await queryOne(
        'SELECT id, active, role, store_id FROM users WHERE id = ?', assignedTargetId);
      if (!target || !target.active || Number(target.store_id) !== Number(row.store_id)
        || NON_PERSONNEL_ROLES.includes(target.role)) {
        return res.status(400).json({ error: 'Geçersiz hedef personel' });
      }
      if (assignedTargetId === Number(row.user_id)) {
        return res.status(400).json({ error: 'Personel kendi vardiyasına atanamaz' });
      }
    }
  }

  if (approve && ROSTER_TYPES.includes(row.type)) {
    // Cizelge onayla birlikte degisir; ayni islemde talep de onaylanir ki
    // yari yolda kalmis (vardiya tasindi ama talep hala bekliyor) bir durum
    // olusmasin.
    try {
      await transaction(async (client) => {
        await cizelgeyeYansit(client, row, assignedTargetId, req.user.id);
        await execute(`
          UPDATE personnel_requests SET status=?, manager_id=?, decision_note=?,
            target_user_id=?,
            decided_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          WHERE id = ?`, [next, req.user.id, note, assignedTargetId, row.id], client);
      });
    } catch (e) {
      if (e.userMessage) return res.status(400).json({ error: e.userMessage });
      if (e.code === '23505') {
        return res.status(400).json({
          error: 'Çizelgede çakışan bir vardiya var (aynı gün aynı vardiya); önce onu düzenleyin',
        });
      }
      throw e;
    }
  } else {
    await execute(`
      UPDATE personnel_requests SET status=?, manager_id=?, decision_note=?,
        decided_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      WHERE id = ?`, next, req.user.id, note, row.id);
  }

  // Talebi acan kisiye karar bildirimi.
  await notify.requestDecided({
    userId: row.user_id,
    approved: approve,
    typeLabel: turAdi(row.type),
    detail: talepOzet(row),
    note,
    byName: req.user.full_name,
    requestId: row.id,
  });

  await logActivity(req.user, approve ? 'TALEP_ONAY' : 'TALEP_RET',
    'personnel_request', row.id,
    `${row.type} talebi ${approve ? 'onaylandı' : 'reddedildi'}`
    + (note ? ` (${note})` : ''), row.store_id);

  res.json({ ok: true, status: next, balances: await balancesOf(row.user_id) });
}

router.post('/requests/:id/approve', requireManager, (req, res) => decide(req, res, 'APPROVED'));
router.post('/requests/:id/reject', requireManager, (req, res) => decide(req, res, 'REJECTED'));

/// Vardiya takas talebinde karsi tarafin mobilden onayi. Yalnizca hedef
/// personel cagirabilir; yonetici onayi bundan SONRA anlamli olur.
router.post('/requests/:id/confirm', async (req, res) => {
  const row = await queryOne('SELECT * FROM personnel_requests WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Talep bulunamadı' });
  if (row.type !== 'VARDIYA_TAKAS') {
    return res.status(400).json({ error: 'Yalnızca vardiya takas talepleri onay bekler' });
  }
  if (Number(row.target_user_id) !== Number(req.user.id)) {
    return res.status(403).json({ error: 'Bu talebi yalnızca hedef personel onaylayabilir' });
  }
  if (row.status !== 'PENDING') {
    return res.status(400).json({ error: 'Bu talep artık bekleyen durumda değil' });
  }
  if (row.target_confirmed_at) return res.status(400).json({ error: 'Bu talebi zaten onayladınız' });

  await execute(`
    UPDATE personnel_requests SET
      target_confirmed_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    WHERE id = ?`, row.id);

  for (const yoneticiId of await kararVericiler(row.store_id, row.user_id)) {
    await notify.requestCreated({
      managerId: yoneticiId,
      requesterName: req.user.full_name,
      typeLabel: 'Vardiya takas onayı verildi',
      detail: talepOzet(row),
      requestId: row.id,
    });
  }
  await logActivity(req.user, 'TALEP_ONAY', 'personnel_request', row.id,
    'Vardiya takas talebine karşı taraf onayı verildi', row.store_id);

  res.json({ ok: true });
});

/// Rapor gorseli. Talep sahibi ve talebin magazasini goren yonetici acabilir.
router.get('/requests/:id/attachment', async (req, res) => {
  const row = await queryOne(
    'SELECT user_id, store_id, attachment FROM personnel_requests WHERE id = ?',
    Number(req.params.id));
  if (!row || !row.attachment) return res.status(404).json({ error: 'Görsel bulunamadı' });
  const isOwner = Number(row.user_id) === Number(req.user.id);
  if (!isOwner && !(MANAGER_ROLES.includes(req.user.role) && allowsStore(req, row.store_id))) {
    return res.status(403).json({ error: 'Bu görsele erişim yetkiniz yok' });
  }
  res.set('Cache-Control', 'private, no-store');
  res.json({ data_url: row.attachment });
});

/// Personel bekleyen kendi talebini geri alabilir.
router.post('/requests/:id/cancel', async (req, res) => {
  const row = await queryOne('SELECT * FROM personnel_requests WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Talep bulunamadı' });
  const isOwner = Number(row.user_id) === Number(req.user.id);
  if (!isOwner && !MANAGER_ROLES.includes(req.user.role)) {
    return res.status(403).json({ error: 'Yalnızca kendi talebinizi geri alabilirsiniz' });
  }
  if (!isOwner && !allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu talebe erişim yetkiniz yok' });
  }
  if (row.status !== 'PENDING') {
    return res.status(400).json({ error: 'Yalnızca bekleyen talep geri alınabilir' });
  }
  await execute("UPDATE personnel_requests SET status = 'CANCELLED' WHERE id = ?", row.id);

  if (isOwner) {
    // Sahibi geri cekti: onay kuyrugunda bekleyen yoneticilere haber.
    for (const yoneticiId of await kararVericiler(row.store_id, row.user_id)) {
      await notify.requestCancelled({
        managerId: yoneticiId,
        requesterName: req.user.full_name,
        typeLabel: turAdi(row.type),
        requestId: row.id,
      });
    }
  } else {
    // Yonetici iptal etti: talebi acan kisi bunu ogrenmeli.
    await notify.requestDecided({
      userId: row.user_id,
      approved: false,
      typeLabel: turAdi(row.type),
      detail: talepOzet(row),
      note: 'Talep yönetici tarafından geri alındı.',
      byName: req.user.full_name,
      requestId: row.id,
    });
  }

  await logActivity(req.user, 'TALEP_IPTAL', 'personnel_request', row.id,
    `${row.type} talebi geri alındı`, row.store_id);
  res.json({ ok: true });
});

module.exports = router;
module.exports.balancesOf = balancesOf;
