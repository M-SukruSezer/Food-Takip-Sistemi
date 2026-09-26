// Bildirim servisi (olay guduml).
//
// Vardiya yayinlandiginda ya da degistiginde calisana bildirim gidiyor.
// Tasarim: OLAY yayinlanir, TASIYICILAR dinler. Boylece gercek push/e-posta
// saglayicisi baglandiginda cagiran kod HIC degismiyor — yeni bir tasiyici
// kaydedilmesi yetiyor.
//
// TASIYICI DURUMU: su an yalnizca veritabani tasiyicisi etkin (bildirim
// kaydediliyor, calisan panelinden goruyor) ve gelistirmede gunluge yaziliyor.
// Push/e-posta MOCK: gercek saglayici yok, o yuzden "gonderildi" demiyoruz,
// "kuyruga alindi" diyoruz.

const { execute } = require('../db');

/// Bildirim turleri.
const KIND = {
  changed: 'SHIFT_CHANGED',
  removed: 'SHIFT_REMOVED',
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
async function dbTransport(n) {
  await execute(
    `INSERT INTO notifications (user_id, kind, title, body, data)
     VALUES (?,?,?,?,?)`,
    n.userId, n.kind, n.title, n.body,
    n.data ? JSON.stringify(n.data) : null,
  );
}

/// Gunluk tasiyicisi: gercek push/e-posta yerine izlenebilir bir satir.
/// PRODUCTION'da sessiz: Vercel gunlukleri kisisel veriyle dolmasin.
function logTransport(n) {
  if (process.env.NODE_ENV === 'production') return;
  // eslint-disable-next-line no-console
  console.log(`[bildirim] ${n.kind} -> kullanici ${n.userId}: ${n.title}`);
}

addTransport(dbTransport);
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
      hatalar.push(e.message);
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

module.exports = { KIND, addTransport, publish, shiftChanged };
