#!/usr/bin/env node
// Web istemcisinin tasarım sistemi koruması.
//
// NEDEN: Flutter tarafında test/responsive_audit_test.dart ekranlara sabit
// renk, sayısal yazı boyutu ve dağınık kırılım noktası yazılmasını engelliyor.
// React'te test altyapısı yok; bu betik aynı kuralları index.css ve JSX
// üzerinde denetler. Kurallar:
//
//   1. Opak renk (#hex) yalnızca index.css'in token bloklarında
//      (:root ve :root[data-theme='dark']) tanımlanır.
//   2. CSS font-size px yazılmaz; --fs-* tip ölçeği kullanılır.
//   3. border-radius px yazılmaz; --radius-* kullanılır.
//   4. Media query genişlikleri yalnızca kırılım tablosundan gelir.
//   5. JSX inline style içinde sayısal fontSize ve #hex renk yazılmaz.
//      (jsPDF tablo stilleri baskı punto ölçüsü olduğu için hariç.)
//
// Kullanım: node scripts/design-guard.js   (çıkış 0 = uyumlu)

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'client', 'src');
const IZINLI_GENISLIK = new Set([359, 560, 640, 641, 899, 900, 1199, 1200]);
const hatalar = [];

function satirNo(metin, indeks) {
  return metin.slice(0, indeks).split('\n').length;
}

// --- index.css --------------------------------------------------------------
const cssYolu = path.join(SRC, 'index.css');
const css = fs.readFileSync(cssYolu, 'utf8');

// İlk iki üst düzey blok token blokları (:root, :root[data-theme='dark']).
let tokenSonu = 0;
for (let i = 0, kapanan = 0; i < css.length && kapanan < 2; i++) {
  if (css.startsWith('\n}\n', i)) {
    kapanan++;
    tokenSonu = i + 3;
  }
}
const govde = css.slice(tokenSonu);
const ofset = tokenSonu;
// Yorumlar denetlenmez (ölçüm notlarında renk değerleri geçiyor).
const yorumsuz = govde.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));

for (const m of yorumsuz.matchAll(/#[0-9a-fA-F]{3,8}\b/g)) {
  hatalar.push(`index.css:${satirNo(css, ofset + m.index)} sabit renk ${m[0]} → token kullanın`);
}
for (const m of yorumsuz.matchAll(/font-size:\s*[0-9.]+px/g)) {
  hatalar.push(`index.css:${satirNo(css, ofset + m.index)} "${m[0]}" → var(--fs-*)`);
}
for (const m of yorumsuz.matchAll(/border-radius:[^;}]*?\b[0-9.]+px/g)) {
  hatalar.push(`index.css:${satirNo(css, ofset + m.index)} "${m[0].trim()}" → var(--radius-*)`);
}
for (const m of yorumsuz.matchAll(/@media[^{]*/g)) {
  for (const g of m[0].matchAll(/(?:min|max)-width:\s*(\d+)px/g)) {
    if (!IZINLI_GENISLIK.has(Number(g[1]))) {
      hatalar.push(`index.css:${satirNo(css, ofset + m.index)} kırılım ${g[1]}px tabloda yok`);
    }
  }
}

// --- JSX ----------------------------------------------------------------------
function jsxDosyalari(dizin) {
  return fs.readdirSync(dizin, { withFileTypes: true }).flatMap((e) => {
    const yol = path.join(dizin, e.name);
    if (e.isDirectory()) return jsxDosyalari(yol);
    return e.name.endsWith('.jsx') ? [yol] : [];
  });
}

for (const dosya of jsxDosyalari(SRC)) {
  const kod = fs.readFileSync(dosya, 'utf8');
  const ad = path.relative(path.join(SRC, '..'), dosya);
  for (const blok of kod.matchAll(/style=\{\{[\s\S]*?\}\}/g)) {
    const satir = satirNo(kod, blok.index);
    if (/fontSize:\s*[0-9]/.test(blok[0])) {
      hatalar.push(`${ad}:${satir} inline sayısal fontSize → 'var(--fs-*)'`);
    }
    const renk = blok[0].match(/#[0-9a-fA-F]{3,8}\b/);
    if (renk) hatalar.push(`${ad}:${satir} inline sabit renk ${renk[0]} → var(--…)`);
  }
}

if (hatalar.length) {
  console.error('Tasarım sistemi ihlalleri:\n  ' + hatalar.join('\n  '));
  process.exit(1);
}
console.log('Tasarım sistemi: uyumlu (renk, tip ölçeği, köşe, kırılım).');
