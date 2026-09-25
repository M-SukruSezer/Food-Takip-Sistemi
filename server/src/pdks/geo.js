// Konum dogrulamasi (geofencing).
//
// KVKK: koordinat kisisel veridir. Burada yalnizca karsilastirma yapilir;
// saklama karari cagiran katmanda verilir.

// Dunyanin ortalama yaricapi (IUGG). Kutup ve ekvator yaricapi arasindaki
// fark magaza olceginde (yuz metreler) fark yaratmaz.
const EARTH_RADIUS_M = 6371008.8;

const toRad = (deg) => (deg * Math.PI) / 180;

/// Iki koordinat arasindaki buyuk daire mesafesi, metre.
///
/// Haversine formulu: kisa mesafelerde duz kosinus formulunden daha kararli
/// (kucuk acilarda kosinus hassasiyet kaybediyor).
function haversineMeters(lat1, lon1, lat2, lon2) {
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/// Gecerli bir koordinat mi?
function isValidCoordinate(lat, lon) {
  return (
    Number.isFinite(lat) && Number.isFinite(lon) &&
    lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 &&
    // Tam (0,0) Gine Korfezi'nde; cihaz konumu alamadiginda bazi istemciler
    // bu degeri gonderiyor. Gercek bir isyeri olmadigi icin reddedilir.
    !(lat === 0 && lon === 0)
  );
}

// Cihazin bildirdigi dogruluk yaricapi bundan buyukse konum guvenilmez.
// 200 m: sehir ici A-GPS tipik olarak 5-30 m verir; 200 m uzeri genellikle
// baz istasyonu ya da IP tabanli tahmin demektir.
const MAX_ACCURACY_M = 200;

// Iki kayit arasinda mumkun sayilan en yuksek hiz (m/s). 90 m/s ~ 324 km/s:
// ucak disinda asilmaz. Asilirsa konum atlamasi (teleport) var.
const MAX_PLAUSIBLE_SPEED_MS = 90;

/// Konumu magazanin geofence'ine gore dogrular.
///
/// Doner: { ok, distance, reason }
///   ok       islem kabul edilebilir mi
///   distance magazaya metre cinsinden uzaklik (hesaplanabildiyse)
///   reason   ok=false ise kullaniciya gosterilecek sebep
///
/// Sahte konum (mock) tespiti: Android/iOS bayragi `isMocked` ile gelir.
/// Web Geolocation API bunu vermedigi icin undefined olabilir; "bilinmiyor"
/// ile "sahte degil" ayri degerlendirilir — bilinmiyorsa engellenmez ama
/// kayda NULL yazilir, rapor bunu ayirt edebilir.
function verifyLocation({ store, latitude, longitude, accuracy, isMocked }) {
  if (store.latitude === null || store.latitude === undefined ||
      store.longitude === null || store.longitude === undefined) {
    return { ok: false, distance: null, reason: 'Bu mağazanın konumu tanımlanmamış' };
  }
  if (!isValidCoordinate(latitude, longitude)) {
    return { ok: false, distance: null, reason: 'Geçerli bir konum alınamadı' };
  }
  if (isMocked === true) {
    return { ok: false, distance: null, reason: 'Sahte konum tespit edildi' };
  }
  if (accuracy !== null && accuracy !== undefined) {
    if (!Number.isFinite(accuracy) || accuracy < 0) {
      return { ok: false, distance: null, reason: 'Konum doğruluğu okunamadı' };
    }
    if (accuracy > MAX_ACCURACY_M) {
      return {
        ok: false,
        distance: null,
        reason: `Konum hassasiyeti yetersiz (±${Math.round(accuracy)} m). `
          + 'Açık alana çıkıp tekrar deneyin.',
      };
    }
  }

  const distance = haversineMeters(
    Number(store.latitude), Number(store.longitude), latitude, longitude
  );
  const radius = Number(store.geofence_radius_m) || 0;
  // Cihazin sapma payi yaricapa eklenir: 100 m yaricapta +-30 m sapmayla
  // 115 m'de gorunen personel aslinda iceride olabilir. Paydan faydalanip
  // cok uzaktan giris yapilmasin diye pay MAX_ACCURACY_M ile sinirli.
  const allowance = Math.min(accuracy || 0, MAX_ACCURACY_M);
  if (distance > radius + allowance) {
    return {
      ok: false,
      distance,
      reason: `İş yerinden ${Math.round(distance)} m uzaktasınız `
        + `(izin verilen ${radius} m)`,
    };
  }
  return { ok: true, distance, reason: null };
}

/// Onceki kayitla arasindaki hiz makul mu?
///
/// Ayni kisi 5 dakika once 300 km uzakta konum bildirmisse biri sahtedir.
/// Bu kontrol mock bayragini desteklemeyen web istemcisinde de calisir.
function detectTeleport(previous, { latitude, longitude, at }) {
  if (!previous || previous.latitude === null || previous.longitude === null) {
    return { teleport: false };
  }
  if (!isValidCoordinate(latitude, longitude)) return { teleport: false };

  const seconds =
    (new Date(at).getTime() - new Date(previous.occurred_at).getTime()) / 1000;
  // Ayni saniye icindeki iki kayitta hiz sonsuza gider; anlamli bir alt
  // sinir olmadan her cift atlama gorunurdu.
  if (!Number.isFinite(seconds) || seconds < 5) return { teleport: false };

  const meters = haversineMeters(
    Number(previous.latitude), Number(previous.longitude), latitude, longitude
  );
  const speed = meters / seconds;
  if (speed <= MAX_PLAUSIBLE_SPEED_MS) return { teleport: false };
  return {
    teleport: true,
    speed,
    meters,
    seconds,
    reason: `Son kayıttan bu yana ${Math.round(meters / 1000)} km `
      + `${Math.round(seconds / 60)} dakikada aşılmış görünüyor`,
  };
}

module.exports = {
  haversineMeters,
  isValidCoordinate,
  verifyLocation,
  detectTeleport,
  EARTH_RADIUS_M,
  MAX_ACCURACY_M,
  MAX_PLAUSIBLE_SPEED_MS,
};
