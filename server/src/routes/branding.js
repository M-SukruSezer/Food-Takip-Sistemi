const express = require('express');
const { queryOne, execute } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();
const MAX_CHARS = 900000;

// Only the public login illustration is exposed before authentication.
router.get('/login', async (req, res) => {
  const row = await queryOne("SELECT value FROM app_settings WHERE key = 'login_image'");
  res.set('Cache-Control', 'no-store');
  res.json({ image: row?.value ?? null });
});

router.put('/login', requireAuth, async (req, res) => {
  if (req.user.role !== 'super_admin') {
    return res.status(403).json({ error: 'Giriş görselini yalnızca super admin değiştirebilir' });
  }
  const image = req.body?.image;
  if (image !== null) {
    if (typeof image !== 'string' || image.length > MAX_CHARS ||
        !/^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/.test(image)) {
      return res.status(400).json({ error: 'Geçerli bir JPEG görseli seçin (en fazla 900 KB veri)' });
    }
    const encoded = image.slice('data:image/jpeg;base64,'.length);
    const bytes = Buffer.from(encoded, 'base64');
    if (bytes.toString('base64') !== encoded || bytes.length < 4 ||
        bytes[0] !== 0xff || bytes[1] !== 0xd8 ||
        bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) {
      return res.status(400).json({ error: 'Görsel biçimi geçersiz' });
    }
  }
  await execute(`INSERT INTO app_settings (key, value, updated_by, updated_at)
    VALUES ('login_image', ?, ?, NOW())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value,
      updated_by = EXCLUDED.updated_by, updated_at = NOW()`, image, req.user.id);
  res.json({ image });
});

module.exports = router;
