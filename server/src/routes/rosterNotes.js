const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth, requireRole, allowsStore, MANAGER_ROLES } = require('../auth');
const { logActivity } = require('../utils');

// Haftalik vardiya planinin altindaki notlar ("Pazar sabah envanter sayimi"
// gibi). Magaza + hafta (pazartesi) basina tutulur; cizelgeyi goren herkes
// okur, yalnizca yoneticiler yazar. Her degisiklik hareket kayitlarina duser.

const router = express.Router();
router.use(requireAuth);
const requireManager = requireRole(...MANAGER_ROLES);

const TARIH = /^\d{4}-\d{2}-\d{2}$/;
const NOT_MAX = 1000;

/// Verilen gunun ISO haftasinin pazartesisi.
function haftaBasi(tarih) {
  const d = new Date(`${tarih}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
}

/// Notun magazasi: istekte verilen ya da kullanicinin kendi magazasi.
function magazaOf(req, res, kaynak) {
  const storeId = kaynak.storeId ? Number(kaynak.storeId) : req.user.store_id;
  if (!storeId) {
    res.status(400).json({ error: 'Not için mağaza seçilmelidir' });
    return null;
  }
  if (!allowsStore(req, storeId)) {
    res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
    return null;
  }
  return Number(storeId);
}

router.get('/roster/notes', async (req, res) => {
  const from = String(req.query.from || '');
  if (!TARIH.test(from)) return res.status(400).json({ error: 'from YYYY-AA-GG biçiminde olmalıdır' });
  const storeId = magazaOf(req, res, req.query);
  if (!storeId) return undefined;
  const rows = await queryAll(`
    SELECT n.id, n.store_id, n.week_start, n.body, n.created_at, n.updated_at,
           c.full_name AS created_by_name, e.full_name AS updated_by_name
    FROM roster_notes n
    LEFT JOIN users c ON c.id = n.created_by
    LEFT JOIN users e ON e.id = n.updated_by
    WHERE n.store_id = ? AND n.week_start = ?
    ORDER BY n.created_at`, storeId, haftaBasi(from));
  res.json(rows);
});

function metin(body) {
  const s = String((body && body.body) || '').trim();
  if (!s) return { error: 'Not boş olamaz' };
  if (s.length > NOT_MAX) return { error: `Not en fazla ${NOT_MAX} karakter olabilir` };
  return { value: s };
}

router.post('/roster/notes', requireManager, async (req, res) => {
  const body = req.body || {};
  const from = String(body.from || '');
  if (!TARIH.test(from)) return res.status(400).json({ error: 'from YYYY-AA-GG biçiminde olmalıdır' });
  const m = metin(body);
  if (m.error) return res.status(400).json({ error: m.error });
  const storeId = magazaOf(req, res, body);
  if (!storeId) return undefined;
  const hafta = haftaBasi(from);
  const r = await execute(`
    INSERT INTO roster_notes (store_id, week_start, body, created_by)
    VALUES (?,?,?,?) RETURNING id`, storeId, hafta, m.value, req.user.id);
  await logActivity(req.user, 'CIZELGE_NOT_EKLE', 'roster_note', r.lastInsertRowid,
    `${hafta} haftası notu: ${m.value}`, storeId);
  res.status(201).json({ id: Number(r.lastInsertRowid), week_start: hafta, body: m.value });
});

async function notVeYetki(req, res) {
  const row = await queryOne('SELECT * FROM roster_notes WHERE id = ?', Number(req.params.id));
  if (!row) {
    res.status(404).json({ error: 'Not bulunamadı' });
    return null;
  }
  if (!allowsStore(req, row.store_id)) {
    res.status(403).json({ error: 'Bu nota erişim yetkiniz yok' });
    return null;
  }
  return row;
}

router.put('/roster/notes/:id', requireManager, async (req, res) => {
  const row = await notVeYetki(req, res);
  if (!row) return undefined;
  const m = metin(req.body);
  if (m.error) return res.status(400).json({ error: m.error });
  await execute(`
    UPDATE roster_notes SET body = ?, updated_by = ?,
      updated_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    WHERE id = ?`, m.value, req.user.id, row.id);
  await logActivity(req.user, 'CIZELGE_NOT_DUZENLE', 'roster_note', row.id,
    `${row.week_start} haftası notu düzenlendi: "${row.body}" → "${m.value}"`, row.store_id);
  res.json({ ok: true });
});

router.delete('/roster/notes/:id', requireManager, async (req, res) => {
  const row = await notVeYetki(req, res);
  if (!row) return undefined;
  await execute('DELETE FROM roster_notes WHERE id = ?', row.id);
  await logActivity(req.user, 'CIZELGE_NOT_SIL', 'roster_note', row.id,
    `${row.week_start} haftası notu silindi: ${row.body}`, row.store_id);
  res.json({ ok: true });
});

module.exports = router;
module.exports.haftaBasi = haftaBasi;
