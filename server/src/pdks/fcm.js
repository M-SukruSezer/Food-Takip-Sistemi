const crypto = require('crypto');

// Firebase Cloud Messaging gonderici (HTTP v1).
//
// NEDEN HTTP v1: eski "server key" ile calisan legacy API 2024'te kapatildi.
// v1 OAuth2 istiyor, o da bir SERVIS HESABI ozel anahtari gerektiriyor.
// google-services.json bunu VERMEZ — o istemci tarafinin yapilandirmasi,
// uygulamanin FCM'e kaydolmasini saglar; gondermeye yetkisi yoktur.
//
// YAPILANDIRMA: Firebase konsolundan indirilen servis hesabi JSON'u tek
// satir olarak FIREBASE_SERVICE_ACCOUNT ortam degiskenine konur.
// Alternatif olarak uc alan ayri ayri verilebilir:
//   FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY
//
// ANAHTAR YOKSA: bu modul sessizce DEVRE DISI kalir. Bilerek boyle —
// bildirim bir yan etki; anahtar tanimli degil diye vardiya kaydinin ya da
// talep onayinin patlamasi kabul edilemez. Istemcideki yoklama yolu
// (PushPoller) uygulama acikken bildirimleri yine de gosteriyor.
//
// BAGIMLILIK EKLENMEDI: googleapis/google-auth-library yerine JWT burada
// crypto ile imzalaniyor. Yapilan is ~40 satir ve sunucu paketini
// sismeden tutuyor.

/// Erisim jetonu onbellegi. Google'in verdigi jeton 1 saat gecerli; her
/// bildirimde yeni jeton istemek gereksiz gecikme ve kota tuketimi olurdu.
let _tokenCache = null; // { token, expiresAt }

/// Yapilandirmayi ortamdan okur. Eksikse null.
function readConfig() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (raw && raw.trim()) {
    try {
      const j = JSON.parse(raw);
      if (j.project_id && j.client_email && j.private_key) {
        return {
          projectId: j.project_id,
          clientEmail: j.client_email,
          privateKey: j.private_key,
        };
      }
    } catch {
      // Bozuk JSON: asagidaki ayri degiskenler denenir.
    }
  }
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  // Ortam degiskenlerinde satir sonlari cogu zaman "\n" metni olarak
  // saklanir; gercek satir sonuna cevrilmezse imza gecersiz olur.
  const privateKey = (process.env.FIREBASE_PRIVATE_KEY || '').replace(/\\n/g, '\n');
  if (projectId && clientEmail && privateKey) {
    return { projectId, clientEmail, privateKey };
  }
  return null;
}

/// FCM gonderimi yapilandirilmis mi.
function isConfigured() {
  return readConfig() !== null;
}

function b64url(input) {
  return Buffer.from(input).toString('base64url');
}

/// Servis hesabi adina imzalanmis JWT. Google bunu erisim jetonuna cevirir.
function buildJwt(cfg, now) {
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: cfg.clientEmail,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(`${header}.${claim}`);
  const sig = signer.sign(cfg.privateKey, 'base64url');
  return `${header}.${claim}.${sig}`;
}

/// Erisim jetonu. Onbellekte gecerlisi varsa onu doner.
async function accessToken(cfg) {
  const now = Math.floor(Date.now() / 1000);
  // 60 sn pay: istek yolda iken jetonun dolmasini engelliyor.
  if (_tokenCache && _tokenCache.expiresAt - 60 > now) return _tokenCache.token;

  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: buildJwt(cfg, now),
    }),
  });
  if (!r.ok) {
    const govde = await r.text();
    throw new Error(`FCM erişim jetonu alınamadı (${r.status}): ${govde.slice(0, 200)}`);
  }
  const j = await r.json();
  _tokenCache = {
    token: j.access_token,
    expiresAt: now + (Number(j.expires_in) || 3600),
  };
  return _tokenCache.token;
}

/// Tek cihaza bildirim gonderir.
///
/// Doner: { ok } ya da { ok: false, invalidToken, fatal, error }
///
/// HIC ISTISNA FIRLATMAZ. Cagiran katman bildirim dongusunun icinde;
/// tek bir cihazin hatasi butun gonderimi durdurmamali.
///
/// invalidToken=true  Jeton ARTIK GECERSIZ (uygulama silinmis, veri
///                    temizlenmis, jeton yenilenmis). Cagiran katman satiri
///                    siliyor; aksi halde olu jetonlar birikir.
/// fatal=true         Sorun jetonda DEGIL yapilandirmada ya da kimlikte
///                    (anahtar yanlis, saat kaymis, ag yok). Diger cihazlari
///                    denemek anlamsiz — cagiran donguden CIKMALI.
async function sendToToken({ token, title, body, data }) {
  const cfg = readConfig();
  if (!cfg) return { ok: false, fatal: true, error: 'FCM yapılandırılmamış' };

  let at;
  try {
    at = await accessToken(cfg);
  } catch (e) {
    // Kimlik alinamadi: bu TUM cihazlari etkiler.
    return { ok: false, fatal: true, error: e.message };
  }
  const url = `https://fcm.googleapis.com/v1/projects/${cfg.projectId}/messages:send`;

  // 'notification' + 'data' birlikte: bildirim uygulama kapaliyken Android
  // tarafindan gosterilir, data ise her iki durumda da uygulamaya ulasir.
  // Yalnizca data gonderilse kapali uygulamada HICBIR SEY gorunmezdi.
  const mesaj = {
    message: {
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data || {}).map(([k, v]) => [k, String(v)])
      ),
      android: {
        priority: 'high',
        notification: {
          // Istemcide onceden olusturulan kanal. Kanal adi eslesmezse
          // Android bildirimi varsayilan (sessiz) kanala dusurur.
          channel_id: 'operasyon_takip_bildirim',
        },
      },
    },
  };

  let r;
  try {
    r = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${at}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(mesaj),
    });
  } catch (e) {
    // Ag hatasi: jetonun sucu degil, silinmemeli.
    return { ok: false, error: `FCM ağ hatası: ${e.message}` };
  }

  if (r.ok) return { ok: true };

  const metin = await r.text();
  // UNREGISTERED / INVALID_ARGUMENT: jeton artik ise yaramaz.
  const gecersiz = r.status === 404
    || metin.includes('UNREGISTERED')
    || metin.includes('NOT_FOUND');
  return {
    ok: false,
    invalidToken: gecersiz,
    error: `FCM ${r.status}: ${metin.slice(0, 200)}`,
  };
}

module.exports = { isConfigured, sendToToken, readConfig };
