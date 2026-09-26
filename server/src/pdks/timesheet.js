const t = require('./time');

// Puantaj: devam kayitlarini vardiya saatleriyle kiyaslayip gunun normal
// calisma, fazla mesai ve eksik surelerini cikarir.
//
// Veritabanina dokunmaz. Girdiler cagiran katmanda toplanir, kural burada;
// boylece maasa donusen hesap duvar saatinden bagimsiz test edilebiliyor.

/// 4857 sayili Is Kanunu m.68 asgari ara dinlenmesi.
///   <= 4 saat        15 dk
///   4 - 7.5 saat     30 dk
///   > 7.5 saat       60 dk
function legalBreakMinutes(presenceMinutes) {
  if (presenceMinutes <= 240) return 15;
  if (presenceMinutes <= 450) return 30;
  return 60;
}

/// Gunden dusulecek mola.
///
/// Vardiyada tanimli mola ile yasal asgari molanin KUCUGU alinir:
///   - 8 saatlik vardiyanin 3. saatinde cikan personelden 60 dk mola dusmek
///     calismasini oldugundan az gosterirdi; yasal asgari 15 dk'ya iner.
///   - Isveren 30 dk mola tanimlamissa 8 saat calisan personelden yasal 60
///     dk yerine tanimli 30 dk dusulur — fazlasini dusmek ucretsiz calisma
///     yaratirdi.
function breakToDeduct(presenceMinutes, configuredBreak) {
  const cfg = Number(configuredBreak) || 0;
  if (cfg <= 0 || presenceMinutes <= 0) return 0;
  return Math.min(cfg, legalBreakMinutes(presenceMinutes));
}

/// Vardiya suresi (dakika). Bitis <= baslangic ise gece yarisini gecer.
function shiftSpanMinutes(startHhmm, endHhmm) {
  const s = t.parseHhmm(startHhmm);
  const e = t.parseHhmm(endHhmm);
  if (s === null || e === null) return null;
  return e > s ? e - s : 24 * 60 - s + e;
}

/// Duvar saati farki, gun donusunu hesaba katarak.
///
/// Gece vardiyasinda 22:00 baslangicina 00:30'da gelen personel 150 dk gec
/// kalmistir, 1290 dk erken degil. Kayit vardiya saatinin +-12 saatinde
/// varsayilir.
function minutesFrom(referenceMinutes, actualMinutes) {
  let diff = actualMinutes - referenceMinutes;
  if (diff > 720) diff -= 1440;
  if (diff < -720) diff += 1440;
  return diff;
}

/// Devam kayitlarini giris-cikis ciftlerine boler.
///
/// Uc ucuncu durum ayri bildirilir:
///   open       kapanmamis giris (hala iceride ya da cikis unutulmus)
///   orphanOut  eslesmeyen cikis (veri bozuk)
function pairLogs(logs) {
  const pairs = [];
  const breaks = [];
  let open = null;
  let openBreak = null;
  let orphanOut = 0;
  let orphanBreak = 0;
  for (const l of logs) {
    if (l.type === 'GIRIS') {
      // Ust uste iki giris: uc nokta olarak ikincisi kullanilir, ilki
      // kapanmamis sayilir. Uclar bunu engelliyor, veri duzeltmesinden
      // gelebilir.
      if (open) orphanOut++;
      open = l;
    } else if (l.type === 'CIKIS') {
      if (!open) { orphanOut++; continue; }
      // Cikista mola hala acik kalmissa mola kapanmamis sayilir: suresi
      // bilinmediginden hic dusulemez, durum bayragi ile bildirilir.
      if (openBreak) { orphanBreak++; openBreak = null; }
      pairs.push({ in: open, out: l });
      open = null;
    } else if (l.type === 'MOLA_BASLA') {
      // Mesai dışında molaya cikilamaz; uc nokta engelliyor, veri
      // duzeltmesinden gelen kayit yine de isaretlenir.
      if (!open) { orphanBreak++; continue; }
      if (openBreak) orphanBreak++;
      openBreak = l;
    } else if (l.type === 'MOLA_BITIR') {
      if (!openBreak) { orphanBreak++; continue; }
      breaks.push({ in: openBreak, out: l });
      openBreak = null;
    }
  }
  return { pairs, breaks, open, openBreak, orphanOut, orphanBreak };
}

/// Kayitli mola sureleri toplami (dakika).
///
/// Mutlak zaman damgalarindan: gece vardiyasinda mola gece yarisini gecebilir
/// ve duvar saati geriye doner.
function recordedBreakMinutes(breaks) {
  let total = 0;
  for (const b of breaks) {
    const ms = new Date(b.out.occurred_at).getTime() - new Date(b.in.occurred_at).getTime();
    if (Number.isFinite(ms) && ms > 0) total += ms / 60000;
  }
  return Math.round(total);
}

/// Bir gunun puantaji.
///
/// shifts: [{ start_time, end_time, break_duration_minutes,
///            late_tolerance_minutes, early_leave_tolerance_minutes,
///            overtime_starts_after_minutes, is_day_off }]
///   Bolunmus vardiyada birden fazla olabilir. O durumda planli sure
///   toplanir, gec kalma EN ERKEN baslangica, erken cikis EN GEC bitise
///   gore olculur — vardiyalari tek tek eslestirmek devam kayitlarindan
///   cikarilamiyor.
/// logs: occurred_at'e gore sirali devam kayitlari
/// leaveDay: o gun onayli GUNLUK izin var mi
/// hourlyLeaveMinutes: o gun onayli saatlik izin (planli sureden duser)
function computeDay({
  workDate,
  shifts = [],
  logs = [],
  leaveDay = false,
  hourlyLeaveMinutes = 0,
  holiday = null,
}) {
  const { pairs, breaks, open, openBreak, orphanOut, orphanBreak } = pairLogs(logs);

  // Fiili bulunma suresi: mutlak zaman damgalarindan: gece vardiyasinda
  // duvar saati geriye dondugu icin damga farki tek dogru kaynak.
  let presence = 0;
  for (const p of pairs) {
    const ms = new Date(p.out.occurred_at).getTime() - new Date(p.in.occurred_at).getTime();
    if (Number.isFinite(ms) && ms > 0) presence += ms / 60000;
  }
  presence = Math.round(presence);

  const working = shifts.filter((s) => !s.is_day_off && s.start_time && s.end_time);
  const isDayOff = shifts.length > 0 && shifts.every((s) => s.is_day_off);
  const noShift = shifts.length === 0;

  let scheduled = 0;
  let breakTotal = 0;
  for (const s of working) {
    const span = shiftSpanMinutes(s.start_time, s.end_time);
    if (span === null) continue;
    scheduled += span;
    breakTotal += Number(s.break_duration_minutes) || 0;
  }

  // Onayli saatlik izin BEKLENEN BULUNMA suresini dusurur.
  const hourly = Math.max(0, Math.round(hourlyLeaveMinutes) || 0);

  // Resmi tatil planli sureyi dusurur: izin hesabinda o gun dusuldugu icin
  // puantajda da calisma gunu sayilmasi tutarsiz olurdu. Tam tatilde planli
  // sure sifir (calisma tamamen fazla mesai), yarim tatilde yarisi.
  //
  // Ustune HAFTA TATILI gibi davranmiyor: hafta tatili zaten ayri isaretli.
  const holidayFull = holiday != null && holiday.half !== true;
  const holidayHalf = holiday != null && holiday.half === true;
  const holidayFactor = holidayFull ? 0 : holidayHalf ? 0.5 : 1;

  const expectedPresence = Math.max(0, Math.round(scheduled * holidayFactor) - hourly);

  // Planli calisma, beklenen bulunmadan AYNI mola kuraliyla cikarilir.
  //
  // Onceki surumde planli sure tam gunun molasiyla (60 dk), fiili calisma
  // kisa gunun molasiyla (30 dk) hesaplaniyordu. Bu tutarsizlik hayali fazla
  // mesai uretiyordu: 2 saat saatlik izin alan personel 30 dk mesai
  // kazaniyordu. Iki taraf ayni kurali kullaninca fark kapaniyor.
  const scheduledWork = Math.max(0, expectedPresence - breakToDeduct(expectedPresence, breakTotal));

  // Mola dusumu: KAYIT VARSA fiili, yoksa tanimli/yasal kucugu.
  //
  // Neden fiili oncelikli: personel mola giris-cikisi okuttuysa gunun gercegi
  // o. Tanimli molayi dusmek, 20 dk mola veren personelden 60 dk dusup
  // ucretsiz calisma yaratirdi; tersi de fazla odeme olurdu.
  //
  // Kayit YOKSA eski kurala donuluyor (geriye donuk uyum): mola adimlari
  // eklenmeden once girilen tum gunler bu yolla hesaplanmaya devam ediyor.
  const hasBreakRecords = breaks.length > 0;
  const recordedBreak = recordedBreakMinutes(breaks);
  const deductedBreak = hasBreakRecords
    ? Math.min(recordedBreak, presence)
    : breakToDeduct(presence, breakTotal);
  const netWorked = Math.max(0, presence - deductedBreak);

  // Yasal asgari ara dinlenmesinin altinda kalan mola, uygulanan dusumu
  // DEGISTIRMEZ (calisilan sure odenmeli) ama m.68 ihlali oldugu icin
  // yoneticiye bildirilir.
  const legalBreak = presence > 0 ? legalBreakMinutes(presence) : 0;
  const breakShortfall = hasBreakRecords && presence > 0
    ? Math.max(0, legalBreak - recordedBreak)
    : 0;

  // Gec kalma / erken cikis: tolerans DISI kisim.
  let lateMinutes = 0;
  let earlyLeaveMinutes = 0;
  if (working.length > 0 && pairs.length > 0) {
    const starts = working.map((s) => t.parseHhmm(s.start_time)).filter((v) => v !== null);
    const ends = working.map((s) => t.parseHhmm(s.end_time)).filter((v) => v !== null);
    const firstIn = t.localMinutes(pairs[0].in.occurred_at);
    const lastOut = t.localMinutes(pairs[pairs.length - 1].out.occurred_at);

    // Bolunmus vardiyada en erken baslangic ve en gec bitis referans alinir.
    const refStart = Math.min(...starts);
    const refEnd = working.length === 1
      ? ends[0]
      : Math.max(...ends);

    const lateRaw = minutesFrom(refStart, firstIn);
    const tol = Math.max(...working.map((s) => Number(s.late_tolerance_minutes) || 0));
    if (lateRaw > tol) lateMinutes = Math.round(lateRaw - tol);

    const earlyRaw = minutesFrom(lastOut, refEnd);
    const tolOut = Math.max(...working.map((s) => Number(s.early_leave_tolerance_minutes) || 0));
    if (earlyRaw > tolOut) earlyLeaveMinutes = Math.round(earlyRaw - tolOut);
  }

  // Onayli gunluk izinde gun izinle kapanir: planli sure izin olarak sayilir,
  // eksik sure cikmaz.
  const leaveMinutes = leaveDay ? scheduledWork : 0;
  const effectiveScheduled = leaveDay ? 0 : scheduledWork;

  const surplus = netWorked - effectiveScheduled;
  const overtimeThreshold = working.length
    ? Math.max(...working.map((s) => Number(s.overtime_starts_after_minutes) ?? 15))
    : 0;

  let overtime = 0;
  let missing = 0;
  if (holidayFull && !isDayOff) {
    // Resmi tatilde calisma tamamen fazla mesai; calismadiysa eksik cikmaz.
    overtime = netWorked;
  } else if (isDayOff) {
    // Hafta tatilinde calisma tamamen fazla mesai: planli sure sifir.
    overtime = netWorked;
  } else if (noShift) {
    // Vardiya atanmamis: siniflandirilmaz, isaretlenir. Yonetici karar verir.
    overtime = 0;
  } else if (surplus > overtimeThreshold) {
    overtime = Math.round(surplus);
  } else if (surplus < 0) {
    missing = Math.round(-surplus);
  }

  const statuses = [];
  if (holiday != null) statuses.push(holidayHalf ? 'YARIM_TATIL' : 'RESMI_TATIL');
  if (noShift && (presence > 0 || open)) statuses.push('VARDIYA_YOK');
  if (isDayOff && presence > 0) statuses.push('TATILDE_CALISMA');
  if (leaveDay) statuses.push('IZINLI');
  if (hourly > 0) statuses.push('SAATLIK_IZIN');
  // Resmi tatilde gelmemek devamsizlik degil.
  if (working.length > 0 && !leaveDay && !holidayFull && presence === 0 && !open) {
    statuses.push('DEVAMSIZ');
  }
  if (open) statuses.push('ACIK_GIRIS');
  if (openBreak) statuses.push('ACIK_MOLA');
  if (orphanOut > 0) statuses.push('ESLESMEYEN_KAYIT');
  if (orphanBreak > 0) statuses.push('ESLESMEYEN_MOLA');
  if (breakShortfall > 0) statuses.push('MOLA_EKSIK');
  if (lateMinutes > 0) statuses.push('GEC_GELDI');
  if (earlyLeaveMinutes > 0) statuses.push('ERKEN_CIKTI');

  return {
    work_date: workDate,
    shift_count: working.length,
    is_day_off: isDayOff,
    no_shift: noShift,
    on_leave: leaveDay,
    holiday_name: holiday?.name ?? null,
    is_holiday: holiday != null,
    // Fiili bulunma (mola dusulmemis).
    presence_minutes: presence,
    expected_presence_minutes: leaveDay ? 0 : expectedPresence,
    deducted_break_minutes: deductedBreak,
    // Mola kaydi var mi; yoksa dusum tanimli molaya gore yapildi.
    has_break_records: hasBreakRecords,
    recorded_break_minutes: recordedBreak,
    break_count: breaks.length,
    // m.68 asgarisinin altinda kalan mola (dakika). Dusume etki etmez.
    break_shortfall_minutes: breakShortfall,
    open_break_since: openBreak ? openBreak.occurred_at : null,
    // Mola dusulmus fiili calisma.
    worked_minutes: netWorked,
    scheduled_minutes: effectiveScheduled,
    leave_minutes: leaveMinutes,
    hourly_leave_minutes: hourly,
    overtime_minutes: overtime,
    missing_minutes: missing,
    // Gec kalma ve erken cikis eksik surenin PARCASI, ustune eklenmez;
    // ayri bildirilir ki yonetici sebebini gorebilsin.
    late_minutes: lateMinutes,
    early_leave_minutes: earlyLeaveMinutes,
    open_since: open ? open.occurred_at : null,
    entry_count: pairs.length,
    orphan_count: orphanOut,
    statuses,
  };
}

/// Gunlerin toplami.
function summarize(days) {
  const sum = (k) => days.reduce((a, d) => a + (d[k] || 0), 0);
  return {
    days: days.length,
    worked_days: days.filter((d) => d.worked_minutes > 0).length,
    absent_days: days.filter((d) => d.statuses.includes('DEVAMSIZ')).length,
    leave_days: days.filter((d) => d.on_leave).length,
    day_off_days: days.filter((d) => d.is_day_off).length,
    holiday_days: days.filter((d) => d.is_holiday).length,
    presence_minutes: sum('presence_minutes'),
    worked_minutes: sum('worked_minutes'),
    // Vardiya atanmamis gunlerin calismasi. worked_minutes'a dahildir ama
    // siniflandirilmadigi icin ayrica gorunur: yonetici bu gunlere vardiya
    // atayip puantaji netlestirmeli.
    unscheduled_minutes: days
      .filter((d) => d.no_shift)
      .reduce((a, d) => a + (d.worked_minutes || 0), 0),
    unscheduled_days: days.filter((d) => d.no_shift && d.worked_minutes > 0).length,
    scheduled_minutes: sum('scheduled_minutes'),
    overtime_minutes: sum('overtime_minutes'),
    missing_minutes: sum('missing_minutes'),
    late_minutes: sum('late_minutes'),
    early_leave_minutes: sum('early_leave_minutes'),
    leave_minutes: sum('leave_minutes'),
    hourly_leave_minutes: sum('hourly_leave_minutes'),
    open_days: days.filter((d) => d.open_since).length,
    recorded_break_minutes: sum('recorded_break_minutes'),
    deducted_break_minutes: sum('deducted_break_minutes'),
    // Yasal asgari molanin altinda kalinan gun sayisi (m.68).
    break_shortfall_days: days.filter((d) => d.break_shortfall_minutes > 0).length,
    open_break_days: days.filter((d) => d.open_break_since).length,
  };
}

module.exports = {
  legalBreakMinutes,
  breakToDeduct,
  recordedBreakMinutes,
  shiftSpanMinutes,
  minutesFrom,
  pairLogs,
  computeDay,
  summarize,
};
