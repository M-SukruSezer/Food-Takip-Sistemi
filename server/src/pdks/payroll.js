// Ucret hak edisi: puantajdan cikan sureleri paraya cevirir.
//
// NE OLDUGU: zamana dayali BRUT HAK EDIS hesabi. Bordro DEGIL — SGK primi,
// gelir vergisi, damga vergisi, AGI, asgari ucret destegi gibi kesintilerin
// hicbiri yok. Bunlari burada uydurmak yanlis net maas uretirdi; ucretlendirme
// kararini veren kisi bu tabloyu bordro programina girdi olarak kullanmali.
//
// Veritabanina dokunmaz. Girdiler cagiran katmanda toplanir, kural burada;
// boylece para hesabi duvar saatinden ve kayitlardan bagimsiz test edilebiliyor.

/// Aylik ucretten saat ucreti turetirken kullanilan calisma suresi.
/// 30 gun x 7.5 saat = 225 saat. Turkiye'de yerlesik olan hesap; asgari ucret
/// tebliglerinde de aylik 225 saat esas alinir.
const MONTHLY_HOURS = 225;

/// 4857 sayili Is Kanunu m.41: fazla calisma ucreti normal saat ucretinin
/// 1,5 katidir.
const OVERTIME_MULTIPLIER = 1.5;

/// Gecerli bir para degeri ya da null.
///
/// null / undefined / bos metin "TANIMSIZ" demek, sifir DEGIL. Bu ayrim
/// kritik: Number(null) === 0 oldugu icin sade bir Number() cevrimi,
/// veritabaninda NULL duran saat ucretini 0 TL okuyup yalnizca aylik maasi
/// tanimli personelin hak edisini sifirliyordu.
const num = (v) => {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
};

/// Gecerli saat ucreti ve hangi tabandan geldigi.
///
/// Saat ucreti GIRILMISSE o kullanilir: kismi zamanli personelde dogrudan
/// tanim daha dogru. Girilmemisse aylik maastan turetilir.
/// Sifir gecerli bir deger ("tanimli ama odenmiyor"), bu yuzden null ile
/// ayri degerlendiriliyor.
function hourlyRateOf(profile) {
  const p = profile || {};
  const direct = num(p.hourly_rate);
  if (direct !== null) return { rate: direct, basis: 'hourly' };
  const monthly = num(p.monthly_salary);
  if (monthly !== null) return { rate: monthly / MONTHLY_HOURS, basis: 'monthly' };
  return { rate: null, basis: null };
}

/// Kurusa yuvarlar. Dakikadan saate cevirirken olusan uzun ondaliklar
/// toplamlarda birikip kurus kaymasi yaratiyordu.
const money = (v) => Math.round((Number(v) || 0) * 100) / 100;

/// Bir donemin hak edisi.
///
/// [summary] timesheet.summarize ciktisi.
/// [profile] pdks_profiles satiri (monthly_salary, hourly_rate, meal_daily).
///
/// Doner: satir satir dokum + brut toplam. Ucret tanimli degilse tum para
/// alanlari null doner ve `defined:false` olur — sifir yazmak "ucretsiz
/// calisiyor" anlamina gelirdi.
function computeWage({ summary, profile } = {}) {
  const s = summary || {};
  const { rate, basis } = hourlyRateOf(profile);
  const mealDaily = num((profile || {}).meal_daily);

  const overtimeMinutes = Math.max(0, Math.round(s.overtime_minutes) || 0);
  const workedMinutes = Math.max(0, Math.round(s.worked_minutes) || 0);
  // worked_minutes fazla mesaiyi ICERIR; normal sure farktan cikar. Ikisini
  // toplamak fazla mesaiyi iki kez odemek olurdu.
  const normalMinutes = Math.max(0, workedMinutes - overtimeMinutes);
  // Yillik izin 4857 m.57 geregi UCRETLI; puantajda planli sure olarak
  // duruyor, hak edise ayri satir olarak giriyor ki gorunur olsun.
  const leaveMinutes = Math.max(0, Math.round(s.leave_minutes) || 0);
  const workedDays = Math.max(0, Math.round(s.worked_days) || 0);

  const hasWage = rate !== null;
  const normalPay = hasWage ? money((normalMinutes / 60) * rate) : null;
  const overtimePay = hasWage
    ? money((overtimeMinutes / 60) * rate * OVERTIME_MULTIPLIER) : null;
  const leavePay = hasWage ? money((leaveMinutes / 60) * rate) : null;
  const mealPay = mealDaily !== null ? money(workedDays * mealDaily) : null;

  const parts = [normalPay, overtimePay, leavePay, mealPay].filter((v) => v !== null);
  const gross = parts.length ? money(parts.reduce((a, b) => a + b, 0)) : null;

  return {
    defined: hasWage || mealDaily !== null,
    basis,                                  // 'hourly' | 'monthly' | null
    hourly_rate: hasWage ? money(rate) : null,
    monthly_salary: num((profile || {}).monthly_salary),
    meal_daily: mealDaily,
    normal_minutes: normalMinutes,
    normal_pay: normalPay,
    overtime_minutes: overtimeMinutes,
    overtime_multiplier: OVERTIME_MULTIPLIER,
    overtime_pay: overtimePay,
    leave_minutes: leaveMinutes,
    leave_pay: leavePay,
    worked_days: workedDays,
    meal_pay: mealPay,
    gross_total: gross,
  };
}

/// Kullaniciya gosterilecek uyarilar. Hesabin neyi KAPSAMADIGI, tahmin
/// edilmesin diye acikca yaziliyor.
const WAGE_NOTES = [
  'Tutarlar BRÜT hak ediştir: SGK primi, gelir ve damga vergisi düşülmemiştir.',
  `Fazla mesai saat ücretin ${OVERTIME_MULTIPLIER} katı hesaplanır (4857 m.41).`,
  `Saat ücreti girilmemişse aylık maaştan türetilir (aylık ÷ ${MONTHLY_HOURS} saat).`,
  'Yemek ücreti günlük tutar × fiilen çalışılan gün sayısıdır; izinli ve devamsız günlerde ödenmez.',
  'Yıllık izin ücretli olduğu için ayrı satır olarak hak edişe dahildir (4857 m.57).',
];

module.exports = {
  MONTHLY_HOURS, OVERTIME_MULTIPLIER,
  hourlyRateOf, computeWage, WAGE_NOTES,
};
