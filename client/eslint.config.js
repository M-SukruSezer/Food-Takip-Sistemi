import globals from 'globals';
import react from 'eslint-plugin-react';

// Bu yapilandirmanin var olma nedeni: "Kaydı Sil" dugmesi tanimlanmamis bir
// islevi cagiriyordu ve Vite bunu derlemede yakalamadigi icin hata sessizce
// yayina cikti. no-undef tam olarak bu sinifi durduruyor.
//
// Kural seti bilerek dar tutuldu: bicim tercihleri degil, calisma zamaninda
// patlayacak hatalar hedefleniyor. Mevcut kodun tamami temiz gecmeli ki
// gurultu olusup uyarilar gorunmez hale gelmesin.
export default [
  {
    ignores: ['dist/**', 'node_modules/**', 'android/**'],
  },
  {
    files: ['**/*.{js,jsx}'],
    plugins: { react },
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      parserOptions: {
        ecmaFeatures: { jsx: true },
      },
      globals: {
        ...globals.browser,
        ...globals.es2021,
      },
    },
    settings: {
      react: { version: 'detect' },
    },
    rules: {
      // Tanimsiz degisken/islev referansi. Asil hedef bu.
      'no-undef': 'error',

      // JSX icinde kullanilan bilesenleri "kullanilmis" sayar; olmadan her
      // bilesen importu yanlis yere kullanilmiyor gorunur.
      'react/jsx-uses-vars': 'error',
      'react/jsx-uses-react': 'error',

      // Kullanilmayan degisken, cogu zaman yarim kalmis bir duzenlemenin izi.
      // Bilesen adlari (buyuk harf) ve _ onekli argumanlar haric.
      'no-unused-vars': ['warn', {
        varsIgnorePattern: '^[A-Z_]',
        argsIgnorePattern: '^_',
        caughtErrors: 'none',
      }],

      // Calisma zamaninda patlayan diger klasikler.
      'no-const-assign': 'error',
      'no-dupe-keys': 'error',
      'no-dupe-args': 'error',
      'no-unreachable': 'error',
      'no-duplicate-case': 'error',
      'no-self-assign': 'error',
      'no-cond-assign': 'error',
      'no-sparse-arrays': 'error',
      'valid-typeof': 'error',
      'use-isnan': 'error',
    },
  },
];
