const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
let saved = null;
let writes = 0;
require.cache[require.resolve('../src/db')] = { exports: {
  queryOne: async () => saved == null ? undefined : { value: saved },
  execute: async (_, image) => { writes++; saved = image; },
} };
require.cache[require.resolve('../src/auth')] = { exports: {
  requireAuth(req, res, next) {
    if (!req.headers['x-test-role']) return res.status(401).json({ error: 'Unauthorized' });
    req.user = { role: req.headers['x-test-role'], id: 1 };
    next();
  },
} };
let server, base;
before(async () => {
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use('/branding', require('../src/routes/branding'));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/branding/login`;
});
after(() => new Promise(resolve => server.close(resolve)));
function put(image, role) {
  return fetch(base, { method: 'PUT', headers: { 'content-type': 'application/json', ...(role ? { 'x-test-role': role } : {}) }, body: JSON.stringify({ image }) });
}
test('public endpoint only exposes the login artwork', async () => {
  const res = await fetch(base);
  assert.deepEqual(await res.json(), { image: null });
  assert.equal(res.headers.get('cache-control'), 'no-store');
});
test('unauthenticated and non-super-admin writes are denied', async () => {
  assert.equal((await put(null)).status, 401);
  for (const role of ['store_manager', 'operations_manager', 'barista', 'hr']) {
    assert.equal((await put(null, role)).status, 403);
  }
  assert.equal(writes, 0);
});
test('super admin cannot save URLs, corrupt payloads or oversized data', async () => {
  for (const image of ['https://example.com/photo.jpg', 'data:image/svg+xml;base64,PHN2Zz4=', 'data:image/jpeg;base64,YmFk', 'x'.repeat(900001), undefined]) {
    assert.equal((await put(image, 'super_admin')).status, 400);
  }
  assert.equal(writes, 0);
});
test('super admin can persist artwork and restore the default', async () => {
  const image = 'data:image/jpeg;base64,/9j/2Q==';
  assert.equal((await put(image, 'super_admin')).status, 200);
  assert.deepEqual(await (await fetch(base)).json(), { image });
  assert.equal((await put(null, 'super_admin')).status, 200);
  assert.deepEqual(await (await fetch(base)).json(), { image: null });
});
