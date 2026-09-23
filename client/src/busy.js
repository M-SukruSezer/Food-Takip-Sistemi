// Acik istek sayaci. API katmani her istekte artirir, bittiginde azaltir;
// sayac sifira dustugunde yukleme katmani kapanir.
let count = 0;
let hideTimer = null;
let visible = false;
const listeners = new Set();

function emit() {
  listeners.forEach((fn) => fn(visible));
}

function show() {
  if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
  if (!visible) { visible = true; emit(); }
}

// Zincirlenen istekler (ornegin satis + listeyi yenileme) arasinda katmanin
// bir anlik kapanip tekrar acilmasi goz tirmaliyor; kisa bir gecikmeyle
// birlesik tek bir katman gibi gorunur.
function scheduleHide() {
  if (hideTimer) clearTimeout(hideTimer);
  hideTimer = setTimeout(() => {
    hideTimer = null;
    visible = false;
    emit();
  }, 180);
}

export function beginBusy() {
  count += 1;
  show();
}

export function endBusy() {
  count = Math.max(0, count - 1);
  if (count === 0) scheduleHide();
}

export function subscribeBusy(fn) {
  listeners.add(fn);
  fn(visible);
  return () => listeners.delete(fn);
}
