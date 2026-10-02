// PIN Dogrulama: 60 sn'de bir degisen 6 haneli kod.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const qr = require('../src/pdks/qr');

const store = { id: 3, qr_secret: 'gizli-sir' };
const T = 1_700_000_000_000;

test('kod 6 haneli rakam ve pencere boyunca sabit', () => {
  const { pin, expires_in, window_seconds } = qr.issuePin(store, T);
  assert.match(pin, /^\d{6}$/);
  assert.equal(window_seconds, 60);
  assert.ok(expires_in > 0 && expires_in <= 60);
  const pencereBasi = Math.floor(T / 60000) * 60000;
  assert.equal(qr.issuePin(store, pencereBasi + 59_000).pin, qr.issuePin(store, pencereBasi).pin);
});

test('güncel ve bir önceki pencerenin kodu geçer, daha eskisi geçmez', () => {
  const pin = qr.issuePin(store, T).pin;
  assert.equal(qr.verifyPin(pin, store, T).ok, true);
  assert.equal(qr.verifyPin(pin, store, T + 60_000).ok, true);
  assert.equal(qr.verifyPin(pin, store, T + 120_000).ok, false);
  // Henuz gosterilmemis (sonraki pencere) kod kabul edilmez.
  assert.equal(qr.verifyPin(qr.issuePin(store, T + 60_000).pin, store, T).ok, false);
});

test('başka mağazanın kodu ve biçimsiz giriş reddedilir', () => {
  const pin = qr.issuePin(store, T).pin;
  assert.equal(qr.verifyPin(pin, { id: 4, qr_secret: 'gizli-sir' }, T).ok, false);
  assert.equal(qr.verifyPin('12345', store, T).ok, false);
  assert.equal(qr.verifyPin('abcdef', store, T).ok, false);
  assert.equal(qr.verifyPin(pin, { id: 3, qr_secret: null }, T).ok, false);
});

test('aynı pencerede aynı kod aynı özeti verir (tekrar kullanım engeli)', () => {
  const pin = qr.issuePin(store, T).pin;
  assert.equal(qr.verifyPin(pin, store, T).tokenHash, qr.verifyPin(pin, store, T + 1000).tokenHash);
});
