import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync } from 'node:fs';

// Profilde gosterilen surum ve derleme numarasi uygulamanin kendi verisinden
// gelir: surum package.json'dan, derleme Vercel'in derledigi commit'ten.
const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));
const build = (process.env.VERCEL_GIT_COMMIT_SHA || process.env.GITHUB_SHA || '').slice(0, 7) || 'yerel';

export default defineConfig({
  plugins: [react()],
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
    __APP_BUILD__: JSON.stringify(build),
  },
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:8181',
    },
  },
});
