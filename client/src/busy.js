// Acik istek sayaci. API katmani her istekte artirir, bittiginde azaltir;
// sayac sifira dustugunde yukleme katmani kapanir.
export const DEFAULT_BUSY_MESSAGE = 'Yükleniyor...';

let count = 0;
let hideTimer = null;
let visible = false;
let message = null;
const listeners = new Set();

function emit() {
  listeners.forEach((fn) => fn(visible ? (message || DEFAULT_BUSY_MESSAGE) : null));
}

function show(nextMessage) {
  if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
  if (nextMessage) message = nextMessage;
  if (!visible || nextMessage) { visible = true; emit(); }
}

// Zincirlenen istekler (ornegin satis + listeyi yenileme) arasinda katmanin
// bir anlik kapanip tekrar acilmasi goz tirmaliyor; kisa bir gecikmeyle
// birlesik tek bir katman gibi gorunur.
function scheduleHide() {
  if (hideTimer) clearTimeout(hideTimer);
  hideTimer = setTimeout(() => {
    hideTimer = null;
    visible = false;
    // Sonraki istek kendi metnini vermezse genel metne donulsun.
    message = null;
    emit();
  }, 180);
}

// busyMessage verilirse katmanda genel metin yerine o yazar.
export function beginBusy(busyMessage) {
  count += 1;
  show(busyMessage);
}

export function endBusy() {
  count = Math.max(0, count - 1);
  if (count === 0) scheduleHide();
}

// Dinleyici, katman kapaliyken null, acikken gosterilecek metni alir.
export function subscribeBusy(fn) {
  listeners.add(fn);
  fn(visible ? (message || DEFAULT_BUSY_MESSAGE) : null);
  return () => listeners.delete(fn);
}
