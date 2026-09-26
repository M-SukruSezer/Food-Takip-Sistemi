#!/usr/bin/env node
// Iki istemcinin gezinme tanimlarini karsilastirir.
//
// NEDEN: React'te /pdks-admin'den alt bar isareti kazara dusuruldu ve magaza
// muduru telefonda vardiya yonetimine ULASAMADI. Flutter'in widget testi ayni
// hatayi aninda yakaladi; React'te test altyapisi olmadigi icin hata gecti.
// Bu betik tam o bosluğu kapatiyor: iki istemcinin alt bar kumesi ayrisirsa
// hata verir.
//
// Kullanim: node scripts/nav-parity.js   (cikis 0 = uyumlu)

const fs = require('fs');
const path = require('path');

const KOK = path.join(__dirname, '..');

/// React: Layout.jsx icindeki { to: '/x', ..., tab: true } ogeleri.
function reactAltBar() {
  const s = fs.readFileSync(
    path.join(KOK, 'client/src/components/Layout.jsx'), 'utf8');
  const yollar = new Set();
  // Her oge tek satirda tanimli; satir bazli okumak ic ice suslu parantez
  // ayristirmaktan daha dayanikli.
  for (const satir of s.split('\n')) {
    const m = satir.match(/\{\s*to:\s*'([^']+)'/);
    if (m && /\btab:\s*true\b/.test(satir)) yollar.add(m[1]);
  }
  return yollar;
}

/// Flutter: nav.dart icindeki NavItem(path: '/x', ... inBottomBar: true).
function flutterAltBar() {
  const s = fs.readFileSync(
    path.join(KOK, 'flutter_app/lib/core/nav.dart'), 'utf8');
  const yollar = new Set();
  // NavItem(...) bloklarini kabaca ayir: path ve inBottomBar ayni blokta.
  for (const blok of s.split('NavItem(').slice(1)) {
    const govde = blok.slice(0, blok.indexOf('),') + 1);
    const m = govde.match(/path:\s*'([^']+)'/);
    if (m && /inBottomBar:\s*true/.test(govde)) yollar.add(m[1]);
  }
  return yollar;
}

const r = reactAltBar();
const f = flutterAltBar();

// Yalnizca iki istemcide de VAR OLAN ekranlari kiyasla: birinde hic olmayan
// bir ekran (orn. yalnizca web'de olan bir rapor) uyumsuzluk sayilmaz.
const reactYollari = new Set(
  fs.readFileSync(path.join(KOK, 'client/src/components/Layout.jsx'), 'utf8')
    .match(/to:\s*'\/[^']+'/g)?.map((x) => x.match(/'([^']+)'/)[1]) || []);
const flutterYollari = new Set(
  fs.readFileSync(path.join(KOK, 'flutter_app/lib/core/nav.dart'), 'utf8')
    .match(/path:\s*'\/[^']+'/g)?.map((x) => x.match(/'([^']+)'/)[1]) || []);
const ortak = [...reactYollari].filter((y) => flutterYollari.has(y));

const sadeceFlutter = ortak.filter((y) => f.has(y) && !r.has(y));
const sadeceReact = ortak.filter((y) => r.has(y) && !f.has(y));

console.log(`React alt bar   : ${[...r].sort().join(', ')}`);
console.log(`Flutter alt bar : ${[...f].sort().join(', ')}`);
console.log(`ortak ekran     : ${ortak.length}`);

if (sadeceFlutter.length === 0 && sadeceReact.length === 0) {
  console.log('\nOK  iki istemcinin alt bar kumesi uyumlu');
  process.exit(0);
}
console.error('\nHATA  alt bar kumeleri ayrismis:');
for (const y of sadeceFlutter) {
  console.error(`  ${y}  Flutter'da alt barda VAR, React'te YOK`);
}
for (const y of sadeceReact) {
  console.error(`  ${y}  React'te alt barda VAR, Flutter'da YOK`);
}
console.error('\nBir ekran bir istemcide alt bardan erisilebilirken digerinde');
console.error('erisilemiyorsa bu genellikle kazara dusurulmus bir isarettir.');
process.exit(1);
