const crypto = require('crypto');

// QR token uretimi ve dogrulamasi.
//
// Iki kip:
//   rotating  Kiosk ekraninda 60 sn'de bir yenilenen token. Fotograflanan
//             token pencere kapaninca gecersiz olur.
//   static    Basili sabit kod. Icerigi hic degismedigi icin TEK BASINA
//             yeterli sayilmaz; cagiran katman konum dogrulamasi da ister.
//
// Magaza sirri (stores.qr_secret) istemciye ASLA gonderilmez; token sirdan
// HMAC ile uretilir, dogrulama sunucuda yapilir.

const ROTATING_PREFIX = 'PDKS1';
const STATIC_PREFIX = 'PDKS1S';
// Personelin telefonunda gosterilen, kiosk/yonetici tarafindan okutulan token.
// Kisiye bagli oldugu icin okutan tarafin kimi kaydettigini bilmesi gerekmez.
const USER_PREFIX = 'PDKSU1';

/// Token penceresi. 60 sn: personelin okutmasi icin yeterli, fotograflanan
/// kodun kullanim omru icin kisa.
const WINDOW_SECONDS = 60;

/// Kabul edilen pencere sapmasi. Kiosk ile telefon saati arasindaki kayma ve
/// okutma gecikmesi icin bir pencere onceye/sonraya izin verilir.
const WINDOW_TOLERANCE = 1;

/// Yeni magaza sirri. 32 bayt, base64url.
function generateSecret() {
  return crypto.randomBytes(32).toString('base64url');
}

function windowIndex(at = Date.now()) {
  return Math.floor(at / 1000 / WINDOW_SECONDS);
}

function sign(secret, payload) {
  return crypto.createHmac('sha256', secret).update(payload).digest('base64url').slice(0, 22);
}

/// Kioskta gosterilecek donen token.
function issueRotatingToken(store, at = Date.now()) {
  if (!store.qr_secret) throw new Error('Mağazanın QR sırrı tanımlanmamış');
  const w = windowIndex(at);
  const sig = sign(store.qr_secret, `${ROTATING_PREFIX}:${store.id}:${w}`);
  return {
    token: `${ROTATING_PREFIX}:${store.id}:${w}:${sig}`,
    // Arayuz sayaci gosterebilsin: bu pencerenin bitisine kalan saniye.
    expires_in: WINDOW_SECONDS - Math.floor((at / 1000) % WINDOW_SECONDS),
    window_seconds: WINDOW_SECONDS,
  };
}

/// Personelin telefonunda gosterecegi donen token.
///
/// Magaza sirriyla imzalanir: yalnizca o magazanin kiosku dogrulayabilir.
/// Personelin cihazi sirri bilmedigi icin token sunucudan alinir.
function issueUserToken(store, userId, at = Date.now()) {
  if (!store.qr_secret) throw new Error('Mağazanın QR sırrı tanımlanmamış');
  const w = windowIndex(at);
  const sig = sign(store.qr_secret, `${USER_PREFIX}:${store.id}:${userId}:${w}`);
  return {
    token: `${USER_PREFIX}:${store.id}:${userId}:${w}:${sig}`,
    expires_in: WINDOW_SECONDS - Math.floor((at / 1000) % WINDOW_SECONDS),
    window_seconds: WINDOW_SECONDS,
  };
}

/// Basilacak sabit kod.
function issueStaticToken(store) {
  if (!store.qr_secret) throw new Error('Mağazanın QR sırrı tanımlanmamış');
  const sig = sign(store.qr_secret, `${STATIC_PREFIX}:${store.id}`);
  return { token: `${STATIC_PREFIX}:${store.id}:${sig}` };
}

/// Sabit zamanli karsilastirma: imza dogrulamasinda erken cikis zamanlama
/// sizintisi yaratir.
function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  if (x.length !== y.length) return false;
  return crypto.timingSafeEqual(x, y);
}

/// Token'dan magaza kimligini okur — hangi magazanin sirriyla dogrulanacagini
/// bulmak icin. Imza burada DOGRULANMAZ.
function peekStoreId(raw) {
  if (typeof raw !== 'string') return null;
  const parts = raw.split(':');
  if (![ROTATING_PREFIX, STATIC_PREFIX, USER_PREFIX].includes(parts[0])) return null;
  const id = Number(parts[1]);
  return Number.isInteger(id) && id > 0 ? id : null;
}

/// Token'i dogrular.
///
/// Doner: { ok, mode, tokenHash, reason }
///   mode      'rotating' | 'static'
///   tokenHash Tekrar kullanimi engellemek icin saklanacak ozet. Sabit kodda
///             null: icerik hic degismedigi icin tekrar korumasi saglamaz,
///             kayda yazilirsa ikinci girisi kalici olarak bloke ederdi.
function verifyToken(raw, store, at = Date.now()) {
  if (typeof raw !== 'string' || raw.length > 200) {
    return { ok: false, reason: 'QR kod okunamadı' };
  }
  const parts = raw.split(':');
  if (!store.qr_secret) {
    return { ok: false, reason: 'Bu mağazada QR ile giriş tanımlı değil' };
  }

  if (parts[0] === STATIC_PREFIX) {
    if (store.qr_mode !== 'static') {
      return { ok: false, reason: 'Bu mağazada sabit QR kod kullanılmıyor' };
    }
    if (parts.length !== 3 || Number(parts[1]) !== Number(store.id)) {
      return { ok: false, reason: 'QR kod bu mağazaya ait değil' };
    }
    const expected = sign(store.qr_secret, `${STATIC_PREFIX}:${store.id}`);
    if (!safeEqual(parts[2], expected)) {
      return { ok: false, reason: 'QR kod geçersiz' };
    }
    return { ok: true, mode: 'static', tokenHash: null, reason: null };
  }

  if (parts[0] === USER_PREFIX) {
    // Personel token'i kiosk tarafindan okutulur; magazanin qr_mode ayari
    // (donen/sabit kiosk kodu) bu akisi ilgilendirmez.
    if (parts.length !== 5 || Number(parts[1]) !== Number(store.id)) {
      return { ok: false, reason: 'QR kod bu mağazaya ait değil' };
    }
    const userId = Number(parts[2]);
    const claimed = Number(parts[3]);
    if (!Number.isInteger(userId) || userId <= 0 || !Number.isInteger(claimed)) {
      return { ok: false, reason: 'QR kod geçersiz' };
    }
    const now = windowIndex(at);
    if (Math.abs(now - claimed) > WINDOW_TOLERANCE) {
      return { ok: false, reason: 'QR kodun süresi doldu, personelden kodu yenilemesini isteyin' };
    }
    const expected = sign(store.qr_secret, `${USER_PREFIX}:${store.id}:${userId}:${claimed}`);
    if (!safeEqual(parts[4], expected)) {
      return { ok: false, reason: 'QR kod geçersiz' };
    }
    return {
      ok: true,
      mode: 'user',
      userId,
      tokenHash: crypto.createHash('sha256').update(raw).digest('hex'),
      reason: null,
    };
  }

  if (parts[0] === ROTATING_PREFIX) {
    if (store.qr_mode !== 'rotating') {
      return { ok: false, reason: 'Bu mağazada dönen QR kod kullanılmıyor' };
    }
    if (parts.length !== 4 || Number(parts[1]) !== Number(store.id)) {
      return { ok: false, reason: 'QR kod bu mağazaya ait değil' };
    }
    const claimed = Number(parts[2]);
    if (!Number.isInteger(claimed)) return { ok: false, reason: 'QR kod geçersiz' };

    const now = windowIndex(at);
    if (Math.abs(now - claimed) > WINDOW_TOLERANCE) {
      return {
        ok: false,
        reason: 'QR kodun süresi doldu, ekrandaki yeni kodu okutun',
      };
    }
    const expected = sign(store.qr_secret, `${ROTATING_PREFIX}:${store.id}:${claimed}`);
    if (!safeEqual(parts[3], expected)) {
      return { ok: false, reason: 'QR kod geçersiz' };
    }
    return {
      ok: true,
      mode: 'rotating',
      // Token'in kendisi degil ozeti saklanir.
      tokenHash: crypto.createHash('sha256').update(raw).digest('hex'),
      reason: null,
    };
  }

  return { ok: false, reason: 'Tanınmayan QR kod' };
}

module.exports = {
  generateSecret,
  issueRotatingToken,
  issueStaticToken,
  issueUserToken,
  verifyToken,
  peekStoreId,
  windowIndex,
  WINDOW_SECONDS,
  WINDOW_TOLERANCE,
  ROTATING_PREFIX,
  STATIC_PREFIX,
  USER_PREFIX,
};
