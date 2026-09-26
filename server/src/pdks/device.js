// Cihaz butunlugu degerlendirmesi: konumu BILDIREN cihaz guvenilir mi?
//
// geo.js konumun NEREDE oldugunu dogrular; burasi konumu ureten cihazi
// degerlendirir. Ikisi farkli karar oldugu icin ayri dosyada.
//
// ONEMLI SINIR: bu bayraklar istemciden gelir, yani KANIT DEGIL. Kurcalanmis
// bir istemci hepsini "temiz" gonderebilir. Bu yuzden guvenlik sinirimiz
// bunlar degil; sunucuda degerlendirilen uc sey:
//   1. donen QR token'i (HMAC, sir yalnizca sunucuda)
//   2. geofence mesafesi
//   3. onceki kayitla arasindaki hiz (teleport)
// Buradaki bayraklar bunlarin UZERINE binen caydirici ve denetim sinyali.

/// Islemi dogrudan reddeden bayraklar. Yalnizca tartismasiz durumlar:
///   mock_location  isletim sisteminin kendisi "bu konum uydurma" diyor
///   emulator       emulatorden gercek bir mesai girisi olamaz
const BLOCKING_FLAGS = ['mock_location', 'emulator'];

/// Kaydedilen ama islemi ENGELLEMEYEN bayraklar.
///
/// Engellenmiyorlar cunku mesru cihazlarda da cok yaygin: gelistirici
/// secenekleri fabrika cikisi acik gelen modeller var, koklu telefon kullanan
/// personel az degil. Engellemek kitlesel yanlis pozitif uretir; bunun yerine
/// kayda islenip yoneticinin ekraninda gorunur.
const WARNING_FLAGS = ['rooted', 'dev_mode', 'usb_debug', 'external_storage', 'unverified'];

const FLAG_LABELS = {
  mock_location: 'Sahte konum tespit edildi',
  emulator: 'Emülatör / gerçek olmayan cihaz',
  rooted: 'Root / jailbreak',
  dev_mode: 'Geliştirici seçenekleri açık',
  usb_debug: 'USB hata ayıklama açık',
  external_storage: 'Uygulama harici depolamada',
  unverified: 'Cihaz kontrolü yapılamadı',
};

const BLOCK_REASONS = {
  mock_location: 'Sahte konum tespit edildi. Sahte konum uygulamasını kapatıp tekrar deneyin.',
  emulator: 'Bu işlem yalnızca gerçek bir telefon ya da tabletten yapılabilir.',
};

/// Istemcinin bildirdigi bayraklari degerlendirir.
///
/// Girdi:
///   isMocked   isletim sisteminin o KONUM OLCUMU icin verdigi bayrak.
///              undefined/null = bilinmiyor (web, iOS) — "sahte degil" DEGIL.
///   integrity  { rooted, emulator, dev_mode, usb_debug, external_storage,
///                checked } — hepsi istege bagli.
///
/// Doner: { flags, blocked, reason }
function assessDevice({ isMocked, integrity } = {}) {
  const flags = [];
  if (isMocked === true) flags.push('mock_location');

  const src = integrity && typeof integrity === 'object' && !Array.isArray(integrity)
    ? integrity : null;
  if (src) {
    if (src.emulator === true) flags.push('emulator');
    if (src.rooted === true) flags.push('rooted');
    if (src.dev_mode === true) flags.push('dev_mode');
    if (src.usb_debug === true) flags.push('usb_debug');
    if (src.external_storage === true) flags.push('external_storage');
    // Istemci kontrolu yapamadigini bildirdi. "Temiz" ile ayni sayilmaz:
    // kutuphaneler hata durumunda false donuyor, o sessizlik kayda gecmeli.
    if (src.checked === false) flags.push('unverified');
  }

  const blocked = flags.find((f) => BLOCKING_FLAGS.includes(f)) || null;
  return { flags, blocked, reason: blocked ? BLOCK_REASONS[blocked] : null };
}

/// Istek govdesinden butunluk bloguu okur. Bilinmeyen anahtarlar atilir ki
/// istemci kayda kendi uydurdugu bayragi yazdiramasin.
function parseIntegrity(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const keys = ['rooted', 'emulator', 'dev_mode', 'usb_debug', 'external_storage', 'checked'];
  const out = {};
  let any = false;
  for (const k of keys) {
    if (typeof raw[k] === 'boolean') { out[k] = raw[k]; any = true; }
  }
  return any ? out : null;
}

/// Bayrak dizisini kolona yazilacak metne cevirir. Bos liste NULL olur:
/// "[]" yazmak "kontrol edildi, temiz" ile "hic bakilmadi" ayrimini bozardi.
function serializeFlags(flags) {
  const clean = (Array.isArray(flags) ? flags : [])
    .filter((f) => BLOCKING_FLAGS.includes(f) || WARNING_FLAGS.includes(f));
  return clean.length ? JSON.stringify([...new Set(clean)]) : null;
}

/// Kolondaki metni diziye cevirir. Bozuk deger bos dizi sayilir.
function parseFlags(raw) {
  if (Array.isArray(raw)) return raw;
  if (typeof raw !== 'string' || !raw.trim()) return [];
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v)
      ? v.filter((f) => BLOCKING_FLAGS.includes(f) || WARNING_FLAGS.includes(f))
      : [];
  } catch (e) {
    return [];
  }
}

/// Bayraklarin Turkce karsiliklari; rapor ve ekranlar icin.
function labelsFor(flags) {
  return parseFlags(flags).map((f) => FLAG_LABELS[f] || f);
}

module.exports = {
  assessDevice, parseIntegrity, serializeFlags, parseFlags, labelsFor,
  BLOCKING_FLAGS, WARNING_FLAGS, FLAG_LABELS,
};
