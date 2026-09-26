const express = require('express');
const { queryAll, queryOne } = require('../db');
const {
  requireAuth,
  roleLevel, resolveStoreScope, storeFilter, allowsStore, MANAGER_ROLES,
  TIMESHEET_VIEW_ROLES,
} = require('../auth');
const dev = require('../pdks/device');
const pay = require('../pdks/payroll');
const cls = require('../pdks/shiftClass');
const bal = require('../pdks/balance');
const sheet = require('../pdks/timesheet');
const t = require('../pdks/time');

const router = express.Router();

router.use(requireAuth);

const isDate = (v) => /^\d{4}-\d{2}-\d{2}$/.test(String(v || ''));

/// Tarih araligindaki tum gunler.
function dateRange(from, to) {
  const out = [];
  let cursor = from;
  for (let guard = 0; guard < 400 && cursor <= to; guard++) {
    out.push(cursor);
    cursor = t.shiftDate(cursor, 1);
  }
  return out;
}

/// Bir veya daha fazla personelin puantaji.
///
/// Sorgular kisi basina degil ARALIK BASINA atilir: 30 gun x 20 personel icin
/// 600 sorgu yerine 4 sorgu.
/// [withWages] ucret hesabi eklensin mi. Maas hassas veri: cagiran katman
/// yetkiyi kontrol edip bu bayragi geciyor, varsayilan KAPALI.
async function buildTimesheet(userIds, from, to, withWages = false) {
  if (userIds.length === 0) return [];
  const ph = userIds.map(() => '?').join(',');

  const users = await queryAll(
    `SELECT u.id, u.full_name, u.role, u.store_id, s.name AS store_name
     FROM users u LEFT JOIN stores s ON s.id = u.store_id
     WHERE u.id IN (${ph}) ORDER BY u.full_name`, ...userIds);

  // Ucret tanimlari. Aralik basina tek sorgu; kisi basina sorgu atmak
  // 20 personelde 20 gidis-donus demekti.
  const wageRows = withWages ? await queryAll(
    `SELECT user_id, monthly_salary, hourly_rate, meal_daily
     FROM pdks_profiles WHERE user_id IN (${ph})`, ...userIds) : [];
  const wageByUser = new Map(wageRows.map((r) => [Number(r.user_id), r]));

  // Resmi tatiller: aralik basina tek sorgu, magaza bazinda haritalanir.
  // Tatil gunu planli sureyi dusuruyor; izin hesabinda dusuldugu icin
  // puantajda calisma gunu sayilmasi tutarsiz olurdu.
  const storeIds = [...new Set(users.map((u) => u.store_id).filter((v) => v != null))];
  const holidayRows = storeIds.length === 0
    ? []
    : await queryAll(`
        SELECT holiday_date, name, is_half_day, store_id FROM public_holidays
        WHERE holiday_date >= ? AND holiday_date <= ?
          AND (store_id IS NULL OR store_id IN (${storeIds.map(() => '?').join(',')}))`,
        from, to, ...storeIds);
  const holidaysByStore = new Map();
  for (const sid of storeIds) {
    holidaysByStore.set(sid, bal.holidayMap(
      holidayRows.filter((h) => h.store_id === null || Number(h.store_id) === Number(sid))
    ));
  }

  const assignments = await queryAll(`
    SELECT us.user_id, us.work_date, us.is_day_off,
           s.start_time, s.end_time, s.break_duration_minutes,
           s.late_tolerance_minutes, s.early_leave_tolerance_minutes,
           s.overtime_starts_after_minutes, s.name AS shift_name
    FROM user_shifts us LEFT JOIN shifts s ON s.id = us.shift_id
    WHERE us.user_id IN (${ph}) AND us.work_date >= ? AND us.work_date <= ?`,
    ...userIds, from, to);

  const logs = await queryAll(`
    SELECT user_id, work_date, type, method, occurred_at, is_valid_location, risk_flags
    FROM attendance_logs
    WHERE user_id IN (${ph}) AND work_date >= ? AND work_date <= ?
    ORDER BY occurred_at, id`, ...userIds, from, to);

  // Onayli gunluk izinler: araliga degen tum talepler.
  const leaves = await queryAll(`
    SELECT user_id, start_at, end_at FROM personnel_requests
    WHERE user_id IN (${ph}) AND type = 'IZIN' AND status = 'APPROVED'
      AND start_at <= ? AND end_at >= ?`, ...userIds, to, from);

  // Onayli saatlik izinler: gune gore dakika toplami.
  const hourly = await queryAll(`
    SELECT user_id, substr(start_at, 1, 10) AS d,
           COALESCE(SUM(hours), 0) * 60 AS minutes
    FROM personnel_requests
    WHERE user_id IN (${ph}) AND type = 'SAATLIK_IZIN' AND status = 'APPROVED'
      AND substr(start_at, 1, 10) >= ? AND substr(start_at, 1, 10) <= ?
    GROUP BY user_id, substr(start_at, 1, 10)`, ...userIds, from, to);

  const key = (u, d) => `${u}|${d}`;
  const byAssignment = new Map();
  for (const a of assignments) {
    const k = key(a.user_id, a.work_date);
    if (!byAssignment.has(k)) byAssignment.set(k, []);
    byAssignment.get(k).push({ ...a, is_day_off: !!a.is_day_off });
  }
  const byLog = new Map();
  for (const l of logs) {
    const k = key(l.user_id, l.work_date);
    if (!byLog.has(k)) byLog.set(k, []);
    byLog.get(k).push(l);
  }
  const byHourly = new Map();
  for (const h of hourly) byHourly.set(key(h.user_id, h.d), Number(h.minutes) || 0);

  const dates = dateRange(from, to);
  return users.map((u) => {
    const userLeaves = leaves.filter((l) => Number(l.user_id) === Number(u.id));
    const userHolidays = holidaysByStore.get(u.store_id) || {};
    const days = dates.map((date) => {
      const day = sheet.computeDay({
        workDate: date,
        shifts: byAssignment.get(key(u.id, date)) || [],
        logs: byLog.get(key(u.id, date)) || [],
        leaveDay: userLeaves.some((l) => date >= l.start_at && date <= l.end_at),
        hourlyLeaveMinutes: byHourly.get(key(u.id, date)) || 0,
        holiday: userHolidays[date] || null,
      });
      const names = (byAssignment.get(key(u.id, date)) || [])
        .map((a) => a.shift_name).filter(Boolean);
      // O gunun kayitlarinda biriken uyari bayraklari. Puantaji onaylayan
      // kisi supheli bir girisi gormeden imzalamasin.
      const dayFlags = [...new Set(
        (byLog.get(key(u.id, date)) || []).flatMap((l) => dev.parseFlags(l.risk_flags))
      )];
      return { ...day, shift_names: names, risk_flags: dayFlags };
    });
    const summary = {
      ...sheet.summarize(days),
      flagged_days: days.filter((d) => d.risk_flags.length > 0).length,
    };
    return {
      user: {
        id: u.id, full_name: u.full_name, role: u.role,
        store_id: u.store_id, store_name: u.store_name,
      },
      days,
      summary,
      // Yetki yoksa alan HIC gonderilmiyor; null gondermek "tanimsiz" ile
      // "gormeye yetkin yok" arasini belirsiz birakirdi.
      ...(withWages
        ? { wage: pay.computeWage({ summary, profile: wageByUser.get(Number(u.id)) }) }
        : {}),
    };
  });
}

/// Puantaj.
///
/// Personel yalnizca kendi puantajini gorur. Yonetici magazasinin tum
/// personelini gorur; userId ile tek kisiye daraltabilir.
router.get('/timesheet', async (req, res) => {
  const from = req.query.from;
  const to = req.query.to;
  if (!isDate(from) || !isDate(to)) {
    return res.status(400).json({ error: 'from ve to YYYY-AA-GG biçiminde olmalıdır' });
  }
  if (to < from) return res.status(400).json({ error: 'Bitiş tarihi başlangıçtan önce olamaz' });
  // 400 gunluk ust sinir: dateRange guard ile ayni; once anlasilir mesaj.
  if (dateRange(from, to).length > 366) {
    return res.status(400).json({ error: 'Aralık en fazla 1 yıl olabilir' });
  }

  // IK yonetici DEGIL ama baskasinin puantajini okur: bu uc salt okunur
  // oldugu icin okuma yetkisi ayri listeden geliyor.
  const canViewOthers = TIMESHEET_VIEW_ROLES.includes(req.user.role);
  let userIds;

  if (!canViewOthers) {
    userIds = [req.user.id];
  } else if (req.query.userId) {
    const id = Number(req.query.userId);
    const u = await queryOne('SELECT id, store_id FROM users WHERE id = ?', id);
    if (!u) return res.status(404).json({ error: 'Personel bulunamadı' });
    if (!allowsStore(req, u.store_id)) {
      return res.status(403).json({ error: 'Bu personele erişim yetkiniz yok' });
    }
    userIds = [id];
  } else {
    const scope = resolveStoreScope(req, res);
    if (!scope.ok) return undefined;
    const f = storeFilter(scope, 'store_id');
    const rows = await queryAll(
      `SELECT id FROM users WHERE active = 1 ${f.sql} ORDER BY full_name`, ...f.params);
    userIds = rows.map((r) => r.id);
    // Cok personel x uzun aralik cevabi sisirir; sinirlanir.
    if (userIds.length * dateRange(from, to).length > 6000) {
      return res.status(400).json({
        error: 'Aralık çok geniş. Daha kısa bir dönem seçin ya da tek personel filtreleyin.',
      });
    }
  }

  // Ucret gorme yetkisi. Maas hassas kisisel veri:
  //   - yoneticiler (magaza muduru ve ustu) erisebildikleri personel icin
  //   - personel YALNIZCA kendi ucretini
  //   - IK GOREMEZ: kapsami "puantaj goruntuleme" olarak tanimlandi, ucret
  //     tanimi ayrica "magaza muduru ve ust yoneticiler" olarak verildi.
  //     Erisimi sonradan genisletmek kolay, sizan veriyi geri almak degil.
  const kendisi = userIds.length === 1 && Number(userIds[0]) === Number(req.user.id);
  const withWages = MANAGER_ROLES.includes(req.user.role) || kendisi;

  const items = await buildTimesheet(userIds, from, to, withWages);
  res.json({
    from, to, items,
    wages_included: withWages,
    // Tum personelin toplami: aylik ozet tablosu icin.
    total: sheet.summarize(items.flatMap((i) => i.days)),
    // Ucret TOPLAMI kisilerin hak edislerinin toplamidir; birlesik ozetten
    // yeniden hesaplanamaz cunku her kisinin saat ucreti farkli.
    ...(withWages ? {
      wage_total: (() => {
        const alan = (k) => items.reduce(
          (a, i) => a + (i.wage && i.wage[k] !== null ? i.wage[k] : 0), 0);
        const tanimli = items.some((i) => i.wage && i.wage.defined);
        return {
          defined: tanimli,
          normal_pay: Math.round(alan('normal_pay') * 100) / 100,
          overtime_pay: Math.round(alan('overtime_pay') * 100) / 100,
          leave_pay: Math.round(alan('leave_pay') * 100) / 100,
          meal_pay: Math.round(alan('meal_pay') * 100) / 100,
          gross_total: Math.round(alan('gross_total') * 100) / 100,
          // Ucreti tanimlanmamis personel: toplam eksik okunmasin.
          undefined_count: items.filter((i) => i.wage && !i.wage.defined).length,
        };
      })(),
    } : {}),
    notes: [
      'Mola kaydı varsa fiili mola düşülür; kayıt yoksa İş Kanunu m.68 asgarisi ile vardiyada tanımlı molanın küçüğü kadar düşülür.',
      'Geç kalma ve erken çıkış eksik sürenin parçasıdır, üstüne eklenmez.',
      'Vardiya atanmamış günlerin çalışması sınıflandırılmaz, ayrıca bildirilir.',
      'Resmi tatilde planlı süre sıfırdır; o gün çalışma tamamen fazla mesai sayılır.',
      ...(withWages ? pay.WAGE_NOTES : []),
    ],
  });
});

/// Toplu vardiya cizelgesi: bir magazanin TUM ekibi x tarih araligi.
///
/// Neden ayri uc: puantaj gecmisi hesaplar, bu ise GELECEGI gosterir. Puantaj
/// ucu her gun icin bulunma, mola ve mesai hesabi yapiyor; cizelge icin bunun
/// hicbiri gerekmiyor ve 30 gun x 20 kisi icin bosa hesap demekti.
///
/// TUM EKIP gorur (barista dahil): kimin ne zaman calistigi ekibin gunluk
/// olarak ihtiyac duydugu bilgi. Ucret ya da puantaj verisi ICERMEZ.
router.get('/roster', async (req, res) => {
  const from = req.query.from;
  const to = req.query.to;
  if (!isDate(from) || !isDate(to)) {
    return res.status(400).json({ error: 'from ve to YYYY-AA-GG biçiminde olmalıdır' });
  }
  if (to < from) return res.status(400).json({ error: 'Bitiş tarihi başlangıçtan önce olamaz' });
  const dates = dateRange(from, to);
  // Cizelge ekranda okunacak; 62 gun iki aylik gorunume yeter.
  if (dates.length > 62) {
    return res.status(400).json({ error: 'Çizelge en fazla 62 gün olabilir' });
  }

  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const f = storeFilter(scope, 'u.store_id');

  // Siralama: once KIDEM (rol kademesi), sonra ISE GIRIS TARIHI (eski olan
  // once), en son ad. hired_at NULL olan personel en sona duser: tarihi
  // bilinmeyeni kidemli saymak yanlis olurdu.
  //
  // Rol kademesi ROLES dizisindeki sira; SQL'de yeniden yazmak yerine
  // veriyi cekip JS'te siraliyoruz ki iki yerde iki farkli kademe tanimi
  // olusmasin.
  const users = (await queryAll(`
    SELECT u.id, u.full_name, u.role, u.store_id, st.name AS store_name,
           p.hired_at
    FROM users u
    LEFT JOIN stores st ON st.id = u.store_id
    LEFT JOIN pdks_profiles p ON p.user_id = u.id
    WHERE u.active = 1 ${f.sql}`, ...f.params))
    .sort((a, b) => {
      const ka = roleLevel(a.role);
      const kb = roleLevel(b.role);
      if (ka !== kb) return ka - kb;
      const ta = a.hired_at || '9999-12-31';
      const tb = b.hired_at || '9999-12-31';
      if (ta !== tb) return ta < tb ? -1 : 1;
      return String(a.full_name).localeCompare(String(b.full_name), 'tr');
    });
  if (users.length === 0) {
    return res.json({ from, to, dates, people: [], holidays: {}, totals: {} });
  }
  const ids = users.map((u) => u.id);
  const ph = ids.map(() => '?').join(',');

  const rows = await queryAll(`
    SELECT us.id AS assignment_id, us.user_id, us.work_date, us.is_day_off,
           s.id AS shift_id, s.name AS shift_name, s.start_time, s.end_time,
           s.break_duration_minutes
    FROM user_shifts us LEFT JOIN shifts s ON s.id = us.shift_id
    WHERE us.user_id IN (${ph}) AND us.work_date >= ? AND us.work_date <= ?
    ORDER BY us.work_date, s.start_time`, ...ids, from, to);

  // Resmi tatiller cizelgede de isaretlenir: plan yapan kisi tatili gormeli.
  const storeIds = [...new Set(users.map((u) => u.store_id).filter((v) => v != null))];
  const holidayRows = storeIds.length === 0 ? [] : await queryAll(`
    SELECT holiday_date, name, is_half_day, store_id FROM public_holidays
    WHERE holiday_date >= ? AND holiday_date <= ?
      AND (store_id IS NULL OR store_id IN (${storeIds.map(() => '?').join(',')}))`,
    from, to, ...storeIds);

  const byUser = new Map();
  for (const r of rows) {
    const k = `${r.user_id}|${r.work_date}`;
    if (!byUser.has(k)) byUser.set(k, []);
    const calisma = !r.is_day_off && r.start_time && r.end_time;
    byUser.get(k).push({
      // Hucre duzenlemesi icin gerekli: istemci bu kimlikle atamayi siliyor.
      assignment_id: r.assignment_id,
      shift_id: r.shift_id,
      shift_name: r.shift_name,
      start_time: r.start_time,
      end_time: r.end_time,
      break_duration_minutes: r.break_duration_minutes,
      is_day_off: !!r.is_day_off,
      // Gece vardiyasi isaretlenir: 22:00-06:00 cizelgede ertesi gune sarkar.
      crosses_midnight: calisma ? t.crossesMidnight(r.start_time, r.end_time) : false,
      // minutes NET calisma: ara dinlenmesi DUSULMUS. Cizelgede "planlanan
      // calisma saati" molayi icermemeli — mola ucretli calisma degil.
      minutes: calisma ? cls.netDakika(r) : 0,
      // Molali toplam sure; "08:00-16:30" araliginin kendisi.
      span_minutes: calisma ? sheet.shiftSpanMinutes(r.start_time, r.end_time) : 0,
      // Renklendirme ve yasal uyarilar (4857 m.63/m.68/m.69).
      category: calisma ? cls.kategori(r.start_time, r.end_time) : null,
      night_minutes: calisma ? cls.geceDakikasi(r.start_time, r.end_time) : 0,
      warnings: calisma ? cls.uyarilar(r) : [],
    });
  }

  const people = users.map((u) => {
    const cells = {};
    for (const d of dates) cells[d] = byUser.get(`${u.id}|${d}`) || [];
    const planned = dates.reduce((a, d) => a
      + cells[d].reduce((x, c) => x + (c.minutes || 0), 0), 0);
    return {
      user: {
        id: u.id, full_name: u.full_name, role: u.role,
        store_id: u.store_id, store_name: u.store_name,
      },
      cells,
      planned_minutes: planned,
      // Atanmis calisma gunu ve hafta tatili sayisi.
      shift_days: dates.filter((d) => cells[d].some((c) => !c.is_day_off)).length,
      day_off_days: dates.filter((d) => cells[d].some((c) => c.is_day_off)).length,
      unassigned_days: dates.filter((d) => cells[d].length === 0).length,
    };
  });

  // Gun bazinda kac kisi calisiyor: eksik kadroyu gormek icin.
  const totals = {};
  for (const d of dates) {
    totals[d] = {
      working: people.filter((p) => p.cells[d].some((c) => !c.is_day_off)).length,
      day_off: people.filter((p) => p.cells[d].some((c) => c.is_day_off)).length,
      unassigned: people.filter((p) => p.cells[d].length === 0).length,
      minutes: people.reduce((a, p) => a
        + p.cells[d].reduce((x, c) => x + (c.minutes || 0), 0), 0),
    };
  }

  res.json({
    from, to, dates, people, totals,
    holidays: bal.holidayMap(holidayRows),
    store: scope.storeId != null
      ? (users.find((u) => Number(u.store_id) === Number(scope.storeId)) || {}).store_name ?? null
      : null,
    // Cizelgeyi degistirebilen roller; arayuz dugmeleri buna gore cizilir.
    can_edit: MANAGER_ROLES.includes(req.user.role),
  });
});

/// Su an iste olanlar. Yonetici ekraninin "anlik durum" listesi.
router.get('/now', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const isManager = MANAGER_ROLES.includes(req.user.role);
  if (!isManager) return res.status(403).json({ error: 'Bu listeyi görme yetkiniz yok' });

  const f = storeFilter(scope, 'u.store_id');
  // Her personelin SON kaydi: giris ise iceride.
  const rows = await queryAll(`
    SELECT u.id, u.full_name, u.role, u.store_id, s.name AS store_name,
           l.type, l.method, l.occurred_at, l.work_date, l.distance_m,
           l.is_valid_location, l.risk_flags
    FROM users u
    LEFT JOIN stores s ON s.id = u.store_id
    LEFT JOIN LATERAL (
      SELECT type, method, occurred_at, work_date, distance_m, is_valid_location,
             risk_flags
      FROM attendance_logs al WHERE al.user_id = u.id
      ORDER BY al.occurred_at DESC, al.id DESC LIMIT 1
    ) l ON true
    WHERE u.active = 1 ${f.sql}
    ORDER BY u.full_name`, ...f.params);

  const today = t.localDate();
  const inside = [];
  const outside = [];
  for (const r of rows) {
    const item = {
      user_id: r.id, full_name: r.full_name, role: r.role,
      store_id: r.store_id, store_name: r.store_name,
      last_type: r.type, last_method: r.method, last_at: r.occurred_at,
      work_date: r.work_date, distance_m: r.distance_m,
      is_valid_location: r.is_valid_location,
      risk_flags: dev.parseFlags(r.risk_flags),
      risk_labels: dev.labelsFor(r.risk_flags),
      // Iceridekinin ne kadar suredir oldugu.
      minutes_since: r.occurred_at
        ? Math.round((Date.now() - new Date(r.occurred_at).getTime()) / 60000)
        : null,
    };
    if (r.type === 'GIRIS') inside.push(item); else outside.push(item);
  }

  res.json({
    as_of: new Date().toISOString(),
    work_date: today,
    inside_count: inside.length,
    inside,
    outside,
  });
});

module.exports = router;
