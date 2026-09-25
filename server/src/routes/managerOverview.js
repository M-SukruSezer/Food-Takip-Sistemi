const express = require('express');
const { queryAll, queryOne } = require('../db');
const { requireAuth, requireRole, resolveStoreScope } = require('../auth');
const dailyReports = require('./dailyReports');

const router = express.Router();

// Ana sayfadaki genel rapor yalnizca magazayi isleten iki rolde gorunur.
const OVERVIEW_ROLES = ['store_manager', 'shift_supervisor'];

router.use(requireAuth, requireRole(...OVERVIEW_ROLES));

const { ALL_FIELDS, derive, systemFoodRange } = dailyReports;

function isoDay(d) {
  return d.toISOString().slice(0, 10);
}

/// Haftanin baslangici (Pazartesi 00:00 UTC) — petty cash limiti haftalik.
function weekStart(date = new Date()) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = (d.getUTCDay() + 6) % 7; // Pazartesi = 0
  d.setUTCDate(d.getUTCDate() - day);
  return d.toISOString();
}

/// Petty cash haftalik limit durumu.
async function pettyCash(storeId) {
  const limitRow = await queryOne(
    'SELECT weekly_amount FROM petty_cash_limits WHERE store_id = ?', storeId
  );
  const ws = weekStart();
  const spentRow = await queryOne(
    'SELECT COALESCE(SUM(amount),0) AS total, COUNT(*) AS c FROM petty_cash_expenses WHERE store_id = ? AND spent_at >= ?',
    storeId, ws
  );
  const limit = limitRow ? Number(limitRow.weekly_amount) || 0 : 0;
  const spent = Number(spentRow.total) || 0;
  return {
    weekly_limit: limit,
    spent_this_week: spent,
    expense_count: Number(spentRow.c) || 0,
    remaining: Math.max(0, limit - spent),
    // Limit tanimli degilse oran anlamsiz; arayuz "limit tanimlanmamis" yazar.
    used_pct: limit > 0 ? spent / limit : null,
    over_limit: limit > 0 && spent > limit,
    week_start: ws,
    limit_set: !!limitRow,
  };
}

/// Ay basindan bugune rapor paneli verileri + ciro hizi ve ay sonu tahmini.
///
/// Ortalama, GECEN gun sayisina degil VERI GIRILMIS gun sayisina bolunur.
/// Girilmemis gunleri sifir saymak ortalamayi yapay olarak dusurur ve tahmini
/// bozar. Kac gunun eksik oldugu `days_missing` ile ayrica bildirilir.
async function revenue(storeId) {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth();
  const monthStart = isoDay(new Date(Date.UTC(year, month, 1)));
  const daysInMonth = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const daysElapsed = now.getUTCDate();
  const todayStr = isoDay(now);

  const rows = await queryAll(
    'SELECT * FROM daily_reports WHERE store_id = ? AND report_date >= ? AND report_date <= ? ORDER BY report_date',
    storeId, monthStart, todayStr
  );

  // Food alanlari kayitli degerden degil canli sistem verisinden gelir.
  const live = await systemFoodRange(storeId, monthStart, todayStr);
  const totals = {};
  for (const f of ALL_FIELDS) totals[f.key] = 0;
  for (const r of rows) {
    const day = live[r.report_date];
    for (const f of ALL_FIELDS) {
      const v = day && day[f.key] !== undefined ? day[f.key] : r[f.key];
      totals[f.key] += Number(v) || 0;
    }
  }

  const daysWithData = rows.length;
  const mtd = totals.net_sales;
  const dailyAvg = daysWithData > 0 ? mtd / daysWithData : null;

  // Bugunun kaydi — rapor paneli olculeriyle.
  const todayRow = rows.find((r) => r.report_date === todayStr) || null;
  let todayMetrics = null;
  if (todayRow) {
    const base = {};
    for (const f of ALL_FIELDS) {
      const day = live[todayStr];
      const v = day && day[f.key] !== undefined ? day[f.key] : todayRow[f.key];
      base[f.key] = Number(v) || 0;
    }
    todayMetrics = { report_date: todayStr, ...base, metrics: derive(base) };
  }

  return {
    month: `${year}-${String(month + 1).padStart(2, '0')}`,
    month_start: monthStart,
    days_in_month: daysInMonth,
    days_elapsed: daysElapsed,
    days_with_data: daysWithData,
    days_missing: Math.max(0, daysElapsed - daysWithData),
    mtd_net_sales: mtd,
    // Ciro hizi: veri girilmis gun basina ortalama NET SALES.
    daily_avg: dailyAvg,
    // Ay sonu tahmini = ciro hizi x aydaki gun sayisi. Veri yoksa null.
    forecast_month_end: dailyAvg === null ? null : dailyAvg * daysInMonth,
    remaining_days: Math.max(0, daysInMonth - daysElapsed),
    month_totals: totals,
    month_metrics: derive(totals),
    today: todayMetrics,
  };
}

/// Urun urun donuk depo stogu ve satis hizina gore yeterlilik.
///
/// Satis hizi son `windowDays` gunun satis adedinden (ikram haric) hesaplanir.
/// Yeterlilik gun sayisi DONUK DEPO stoguna gore verilir; cozulmekte olan ve
/// food dolabindaki adetler ayrica gosterilir.
async function stockCoverage(storeId, windowDays) {
  const since = new Date(Date.now() - windowDays * 24 * 3600 * 1000).toISOString();

  const stock = await queryAll(`
    SELECT b.product_type_id AS pid, pt.name, pt.unit_price,
           COALESCE(SUM(CASE WHEN b.status = 'frozen' THEN b.remaining ELSE 0 END),0) AS frozen_qty,
           COALESCE(SUM(CASE WHEN b.status = 'thawing' THEN b.remaining ELSE 0 END),0) AS thawing_qty,
           COALESCE(SUM(CASE WHEN b.status = 'food_cabinet' THEN b.remaining ELSE 0 END),0) AS cabinet_qty
    FROM batches b
    JOIN product_types pt ON pt.id = b.product_type_id
    WHERE b.store_id = ? AND b.status IN ('frozen','thawing','food_cabinet')
    GROUP BY b.product_type_id, pt.name, pt.unit_price
  `, storeId);

  const sold = await queryAll(`
    SELECT b.product_type_id AS pid, pt.name, pt.unit_price,
           COALESCE(SUM(sl.quantity),0) AS qty
    FROM sales sl
    JOIN batches b ON b.id = sl.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    WHERE sl.kind = 'sale' AND sl.store_id = ? AND sl.sold_at >= ?
    GROUP BY b.product_type_id, pt.name, pt.unit_price
  `, storeId, since);

  // Iki yonu de birlestir: stogu olup satilmayan da, satilip stogu bitmis de
  // listede gorunmeli. Ikincisi zaten en acil durum.
  const byId = new Map();
  const slot = (r) => {
    let e = byId.get(r.pid);
    if (!e) {
      e = {
        product_type_id: r.pid,
        name: r.name,
        unit_price: r.unit_price === null ? null : Number(r.unit_price),
        frozen_qty: 0, thawing_qty: 0, cabinet_qty: 0, sold_qty: 0,
      };
      byId.set(r.pid, e);
    }
    return e;
  };
  for (const r of stock) {
    const e = slot(r);
    e.frozen_qty = Number(r.frozen_qty) || 0;
    e.thawing_qty = Number(r.thawing_qty) || 0;
    e.cabinet_qty = Number(r.cabinet_qty) || 0;
  }
  for (const r of sold) slot(r).sold_qty = Number(r.qty) || 0;

  const items = [...byId.values()].map((e) => {
    const velocity = e.sold_qty / windowDays;
    const available = e.frozen_qty + e.thawing_qty + e.cabinet_qty;
    // Hic satmayan urunde yeterlilik gunu tanimsiz: sifira bolme yok.
    const cover = velocity > 0 ? e.frozen_qty / velocity : null;
    const coverAll = velocity > 0 ? available / velocity : null;
    return {
      ...e,
      available_qty: available,
      frozen_value: e.unit_price === null ? null : e.frozen_qty * e.unit_price,
      daily_velocity: velocity,
      days_of_cover: cover,
      days_of_cover_available: coverAll,
      depletion_date: cover === null ? null
        : isoDay(new Date(Date.now() + cover * 24 * 3600 * 1000)),
      // Arayuz renklendirmesi icin: 0 = stok yok, 1 = 3 gunden az, 2 = 7
      // gunden az, 3 = yeterli, null = satis yok, hiz hesaplanamaz.
      risk: velocity === 0 ? null
        : e.frozen_qty === 0 ? 0
        : cover < 3 ? 1
        : cover < 7 ? 2
        : 3,
    };
  });

  // En acil once: satis hizi olanlar yeterlilige gore, satmayanlar sonda.
  items.sort((a, b) => {
    if (a.days_of_cover === null && b.days_of_cover === null) return b.frozen_qty - a.frozen_qty;
    if (a.days_of_cover === null) return 1;
    if (b.days_of_cover === null) return -1;
    return a.days_of_cover - b.days_of_cover;
  });

  return { window_days: windowDays, since, items };
}

router.get('/', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const storeId = scope.storeId || req.user.store_id;
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });

  const n = Number(req.query.days);
  const windowDays = Number.isInteger(n) && n >= 1 && n <= 90 ? n : 14;

  const store = await queryOne('SELECT id, name FROM stores WHERE id = ?', storeId);

  res.json({
    store: store || { id: storeId, name: null },
    petty_cash: await pettyCash(storeId),
    revenue: await revenue(storeId),
    stock: await stockCoverage(storeId, windowDays),
  });
});

module.exports = router;
