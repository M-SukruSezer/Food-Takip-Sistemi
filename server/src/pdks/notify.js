// Bildirim servisi (olay guduml).
//
// Vardiya yayinlandiginda ya da degistiginde calisana bildirim gidiyor.
// Tasarim: OLAY yayinlanir, TASIYICILAR dinler. Boylece gercek push/e-posta
// saglayicisi baglandiginda cagiran kod HIC degismiyor — yeni bir tasiyici
// kaydedilmesi yetiyor.
//
// TASIYICILAR:
//   dbTransport   bildirimi kalici yazar; uygulama ici liste bunu okuyor.
//   fcmTransport  Firebase Cloud Messaging ile TELEFONA gonderir.
//   logTransport  gelistirmede izlenebilir bir satir.
//
// E-posta hala yok.

const { execute, queryAll } = require('../db');
const fcm = require('./fcm');

/// Bildirim turleri.
const KIND = {
  changed: 'SHIFT_CHANGED',
  removed: 'SHIFT_REMOVED',
  published: 'SHIFT_PUBLISHED',
  requestCreated: 'REQUEST_CREATED',
  requestDecided: 'REQUEST_DECIDED',
  requestCancelled: 'REQUEST_CANCELLED',
  deviceBlocked: 'DEVICE_BLOCKED',
};

/// Kayitli tasiyicilar. Her biri async (bildirim) => void.
const transports = [];

/// Tasiyici ekler. Test ve gercek saglayici baglanmasi ayni yoldan geciyor.
function addTransport(fn) {
  transports.push(fn);
  return () => {
    const i = transports.indexOf(fn);
    if (i >= 0) transports.splice(i, 1);
  };
}

/// Veritabani tasiyicisi: bildirimi kalici yazar.
///
/// Uretilen kimligi bildirim nesnesine YAZIYOR: FCM tasiyicisi bu kimligi
/// telefona gonderiyor, istemci de onunla tekrar gosterimi engelliyor.
/// Bu yuzden dbTransport FCM'den ONCE kayitli olmali.
async function dbTransport(n) {
  const r = await execute(
    `INSERT INTO notifications (user_id, kind, title, body, data)
     VALUES (?,?,?,?,?) RETURNING id`,
    n.userId, n.kind, n.title, n.body,
    n.data ? JSON.stringify(n.data) : null,
  );
  n.id = Number(r.lastInsertRowid);
}

/// Uretimde SESSIZ tani izi. Bildirim yolu tamamen sessizdi ve bir FCM
/// sorunu teshis edilemedi; bu iz olmadan "gonderildi mi" sorusunun cevabi
/// yok. Kisisel veri yazilmiyor: yalnizca kullanici kimligi ve sonuc.
function _iz(mesaj) {
  if (process.env.NODE_ENV === 'production' && !process.env.PUSH_DEBUG) return;
  // eslint-disable-next-line no-console
  console.log(`[push] ${mesaj}`);
}

/// Gunluk tasiyicisi: gercek push/e-posta yerine izlenebilir bir satir.
/// PRODUCTION'da sessiz: Vercel gunlukleri kisisel veriyle dolmasin.
function logTransport(n) {
  if (process.env.NODE_ENV === 'production') return;
  // eslint-disable-next-line no-console
  console.log(`[bildirim] ${n.kind} -> kullanici ${n.userId}: ${n.title}`);
}

/// FCM tasiyicisi: kullanicinin KAYITLI TUM cihazlarina gonderir.
///
/// Anahtar tanimli degilse sessizce cikar — bildirim bir yan etki, eksik
/// yapilandirma yuzunden cagiran islemin patlamasi kabul edilemez.
///
/// GECERSIZ JETON TEMIZLIGI: FCM bir jetonun artik gecersiz oldugunu
/// soylerse satir SILINIYOR. Yapilmazsa olu jetonlar birikir ve her
/// bildirimde bosuna istek atilir.
async function fcmTransport(n) {
  if (!fcm.isConfigured()) {
    _iz('FCM yapılandırılmamış, atlandı');
    return;
  }
  const cihazlar = await queryAll(
    'SELECT token FROM device_tokens WHERE user_id = ?', n.userId);
  _iz(`kullanıcı ${n.userId} için ${cihazlar.length} cihaz`);
  if (cihazlar.length === 0) return;

  for (const c of cihazlar) {
    const sonuc = await fcm.sendToToken({
      token: c.token,
      title: n.title,
      body: n.body,
      // Istemci bunlarla "en son gorulen" isaretini ilerletiyor; olmazsa
      // yoklayici ayni bildirimi bir kez daha gosterir.
      data: {
        notification_id: n.id ?? '',
        user_id: n.userId,
        kind: n.kind,
        ...(n.data || {}),
      },
    });
    _iz(`gönderim: ok=${sonuc.ok} fatal=${!!sonuc.fatal} `
      + `gecersiz=${!!sonuc.invalidToken} ${sonuc.error || ''}`);
    if (sonuc.ok) continue;
    if (sonuc.invalidToken) {
      // Olu jeton: satir silinmezse her bildirimde bosuna istek atilir.
      await execute('DELETE FROM device_tokens WHERE token = ?', c.token);
      continue;
    }
    // Yapilandirma/kimlik hatasi tum cihazlari etkiler; kalanlari denemek
    // yalnizca gecikme uretir.
    if (sonuc.fatal) break;
  }
}

addTransport(dbTransport);
addTransport(fcmTransport);
addTransport(logTransport);

/// Bildirimi tum tasiyicilara verir.
///
/// HATA YONETIMI: bir tasiyici patlarsa DIGERLERI calismaya devam eder ve
/// cagiran islem BOZULMAZ. Bildirim gonderilemedigi icin vardiya atamasinin
/// geri alinmasi yanlis olurdu — asil is atamadir, bildirim yan etkidir.
async function publish(n) {
  const hatalar = [];
  for (const fn of transports) {
    try {
      await fn(n);
    } catch (e) {
      hatalar.push(`${fn.name || 'tasiyici'}: ${e.message}`);
      // Hata YUTULMUYOR, sessizce gecilmiyor: cagiran islem bozulmasin diye
      // yayilmiyor ama gunluge DUSUYOR. Bu satir olmadigi icin bir FCM
      // hatasi teshis edilemedi — "delivered" sayisina bakan da yoktu.
      // eslint-disable-next-line no-console
      console.error(`[bildirim HATASI] ${fn.name || 'tasiyici'}: ${e.message}`);
    }
  }
  return { delivered: transports.length - hatalar.length, errors: hatalar };
}

/// Tek gunun vardiyasi degisti.
async function shiftChanged({ userId, workDate, oldLabel, newLabel, byName }) {
  const removed = newLabel == null;
  return publish({
    userId,
    kind: removed ? KIND.removed : KIND.changed,
    title: removed ? 'Vardiyanız kaldırıldı' : 'Vardiyanız değişti',
    body: `${workDate}: `
      + (removed
        ? `${oldLabel ?? 'vardiya'} kaldırıldı.`
        : oldLabel
          ? `${oldLabel} yerine ${newLabel}.`
          : `${newLabel} atandı.`)
      + (byName ? ` Değiştiren: ${byName}.` : ''),
    data: { work_date: workDate, screen: '/roster' },
  });
}

/// Haftalik plan ekiple paylasildi.
///
/// Kisi basina TEK bildirim: haftada 7 gun icin 7 bildirim gondermek
/// bildirim listesini kullanilamaz hale getirirdi.
async function shiftPublished({ userId, from, to, summary, byName }) {
  return publish({
    userId,
    kind: KIND.published,
    title: 'Haftalık vardiya planı paylaşıldı',
    body: `${from} – ${to} haftası`
      + (summary ? `: ${summary}` : '')
      + (byName ? ` Paylaşan: ${byName}.` : ''),
    data: { from, to, screen: '/roster' },
  });
}

/// Talep olusturuldu — KARAR VERECEK yoneticilere gider.
async function requestCreated({ managerId, requesterName, typeLabel, detail, requestId }) {
  return publish({
    userId: managerId,
    kind: KIND.requestCreated,
    title: 'Yeni personel talebi',
    body: `${requesterName}: ${typeLabel}${detail ? ` — ${detail}` : ''}`,
    data: { request_id: requestId, screen: '/pdks' },
  });
}

/// Talep karara baglandi — TALEBI ACAN kisiye gider.
async function requestDecided({ userId, approved, typeLabel, detail, note, byName, requestId }) {
  return publish({
    userId,
    kind: KIND.requestDecided,
    title: approved ? 'Talebiniz onaylandı' : 'Talebiniz reddedildi',
    body: `${typeLabel}${detail ? ` (${detail})` : ''} `
      + (approved ? 'onaylandı.' : 'reddedildi.')
      + (note ? ` Not: ${note}` : '')
      + (byName ? ` Karar veren: ${byName}.` : ''),
    data: { request_id: requestId, screen: '/pdks' },
  });
}

/// Talep sahibi talebini geri cekti — yoneticiye bilgi.
async function requestCancelled({ managerId, requesterName, typeLabel, requestId }) {
  return publish({
    userId: managerId,
    kind: KIND.requestCancelled,
    title: 'Talep geri çekildi',
    body: `${requesterName} ${typeLabel} talebini geri çekti.`,
    data: { request_id: requestId, screen: '/pdks' },
  });
}

module.exports = {
  KIND,
  addTransport,
  publish,
  shiftChanged,
  shiftPublished,
  requestCreated,
  requestDecided,
  requestCancelled,
};
