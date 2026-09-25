CREATE TABLE IF NOT EXISTS stores (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT REFERENCES stores(id),
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('super_admin', 'operations_manager', 'regional_manager', 'store_manager', 'shift_supervisor', 'barista')),
  avatar TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

CREATE TABLE IF NOT EXISTS product_types (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT REFERENCES stores(id),
  name TEXT NOT NULL,
  skt_days INTEGER NOT NULL DEFAULT 3 CHECK (skt_days BETWEEN 1 AND 14),
  unit_price DOUBLE PRECISION,
  description TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

CREATE TABLE IF NOT EXISTS batches (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id),
  product_type_id BIGINT NOT NULL REFERENCES product_types(id),
  batch_code TEXT,
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  remaining INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'frozen' CHECK (status IN ('frozen', 'thawing', 'food_cabinet', 'sold', 'discarded')),
  entered_frozen_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  thawing_started_at TEXT,
  thawing_finish_at TEXT,
  food_cabinet_entered_at TEXT,
  skt_end TEXT,
  sold_at TEXT,
  discarded_at TEXT,
  discard_reason TEXT,
  notes TEXT,
  created_by BIGINT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

CREATE TABLE IF NOT EXISTS sales (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id),
  batch_id BIGINT NOT NULL REFERENCES batches(id),
  quantity INTEGER NOT NULL CHECK (quantity >= 1),
  unit_price DOUBLE PRECISION,
  -- 'sale' satis, 'ikram' bedelsiz verilen urun. Ikram stoktan duser ama
  -- ciroya ve satis adetlerine girmez; degeri bilinsin diye unit_price yine
  -- yazilir.
  kind TEXT NOT NULL DEFAULT 'sale',
  sold_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  sold_by BIGINT
);

CREATE TABLE IF NOT EXISTS activity_logs (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT,
  user_id BIGINT,
  username TEXT,
  action TEXT NOT NULL,
  entity_type TEXT,
  entity_id BIGINT,
  details TEXT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

CREATE TABLE IF NOT EXISTS transfer_approvals (
  id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES batches(id),
  store_id BIGINT NOT NULL REFERENCES stores(id),
  requested_by BIGINT,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  requested_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  decided_by BIGINT,
  decided_at TEXT,
  decision_note TEXT
);

CREATE TABLE IF NOT EXISTS discards (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id),
  batch_id BIGINT NOT NULL REFERENCES batches(id),
  quantity INTEGER NOT NULL CHECK (quantity >= 1),
  reason TEXT,
  discarded_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  discarded_by BIGINT
);

-- Mevcut kurulumlar icin kolon eklemeleri (initialize her soguk baslatmada calistirir)
ALTER TABLE product_types ADD COLUMN IF NOT EXISTS unit_price DOUBLE PRECISION;
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS permissions TEXT;

-- Rol kademeleri genisledi: staff -> barista, araya operations_manager,
-- regional_manager ve shift_supervisor girdi.
-- Sira onemli: kisit once dusurulur, satirlar tasinir, sonra yeni kisit
-- eklenir. Ters sirada ADD CONSTRAINT hala 'staff' olan satirlara takiliyor.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
UPDATE users SET role = 'barista' WHERE role = 'staff';
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('super_admin', 'operations_manager', 'regional_manager', 'store_manager', 'shift_supervisor', 'barista'));

-- Operations/regional manager birden fazla magazadan sorumlu olabilir; tek
-- users.store_id yetmiyor. Diger roller tek magazaya bagli kalir.
CREATE TABLE IF NOT EXISTS user_stores (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, store_id)
);
CREATE INDEX IF NOT EXISTS idx_user_stores_user ON user_stores(user_id);
-- Yetki sistemi gelmeden once her kullanici imha ve ikram yapabiliyordu;
-- mevcut hesaplar bu yetkileri kaybetmesin diye bir kez doldurulur.
-- NULL kosulu sayesinde sonradan yetkisi elinden alinan kullanici (ornegin
-- '["discard"]') tekrar doldurulmaz.
UPDATE users SET permissions = '["discard","ikram"]'
WHERE permissions IS NULL AND role <> 'super_admin';
ALTER TABLE sales ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'sale';
CREATE INDEX IF NOT EXISTS idx_sales_kind ON sales(kind);

CREATE INDEX IF NOT EXISTS idx_batches_status ON batches(status);
CREATE INDEX IF NOT EXISTS idx_batches_store ON batches(store_id);
CREATE INDEX IF NOT EXISTS idx_batches_skt_end ON batches(skt_end);
CREATE INDEX IF NOT EXISTS idx_sales_batch ON sales(batch_id);
CREATE INDEX IF NOT EXISTS idx_sales_store ON sales(store_id);
CREATE INDEX IF NOT EXISTS idx_logs_store ON activity_logs(store_id);
CREATE INDEX IF NOT EXISTS idx_approvals_batch ON transfer_approvals(batch_id);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON transfer_approvals(status);

-- Imhalar adetli olarak discards tablosunda tutulur. Eskiden kismi imhalarin
-- adedi hicbir yerde saklanmiyordu ve tam imhalar remaining'i 0'a cektigi icin
-- raporlardaki imha toplami her zaman 0 cikiyordu.
-- Asagidaki aktarim, gecmis TAM imhalari (adet = parti adedi - satilan) bir
-- kereye mahsus tasir; NOT EXISTS sayesinde her acilista tekrar calissa da
-- yeniden eklemez. Gecmis KISMI imhalar yalnizca hareket kayitlarinda
-- oldugu icin kurtarilamaz.
INSERT INTO discards (store_id, batch_id, quantity, reason, discarded_at)
SELECT b.store_id, b.id,
       b.quantity - COALESCE((SELECT SUM(s.quantity) FROM sales s WHERE s.batch_id = b.id), 0),
       COALESCE(b.discard_reason, 'Gecmis kayittan aktarildi'),
       COALESCE(b.discarded_at, b.created_at)
FROM batches b
WHERE b.status = 'discarded'
  AND b.quantity - COALESCE((SELECT SUM(s.quantity) FROM sales s WHERE s.batch_id = b.id), 0) > 0
  AND NOT EXISTS (SELECT 1 FROM discards d WHERE d.batch_id = b.id);

CREATE INDEX IF NOT EXISTS idx_discards_store ON discards(store_id);
CREATE INDEX IF NOT EXISTS idx_discards_batch ON discards(batch_id);
CREATE INDEX IF NOT EXISTS idx_discards_at ON discards(discarded_at);

-- ---------------------------------------------------------------------------
-- Petty Cash: magaza kasasindan yapilan kucuk masraflar.
-- Limit magaza basina HAFTALIK; Ana Yonetici belirler. Store Manager ve
-- Shift Supervisor ayni kasayi paylasir.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS petty_cash_limits (
  store_id BIGINT PRIMARY KEY REFERENCES stores(id) ON DELETE CASCADE,
  weekly_amount DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (weekly_amount >= 0),
  updated_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  updated_by BIGINT
);

CREATE TABLE IF NOT EXISTS petty_cash_expenses (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  amount DOUBLE PRECISION NOT NULL CHECK (amount > 0),
  description TEXT NOT NULL,
  -- Fis/fatura fotosu data URL olarak; istemci 1000px'e kuculterek gonderir.
  receipt TEXT,
  spent_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  created_by BIGINT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);
CREATE INDEX IF NOT EXISTS idx_petty_store_date ON petty_cash_expenses(store_id, spent_at);

-- ---------------------------------------------------------------------------
-- Gunluk operasyon raporu. Store Manager / Shift Supervisor her gun icin
-- ham verileri girer; oranlar (AT, IPT, FOOD MARKOUT %, FOOD UPH,
-- MODIFIERS %, APP%) saklanmaz, okuma sirasinda hesaplanir. Boylece rapor
-- her zaman tutarli kalir ve hesap hatasi girilemez.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_reports (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  report_date TEXT NOT NULL,                        -- YYYY-MM-DD
  net_sales DOUBLE PRECISION NOT NULL DEFAULT 0,    -- NET SALES
  adt INTEGER NOT NULL DEFAULT 0,                   -- kesilen fis adedi
  product_qty INTEGER NOT NULL DEFAULT 0,           -- toplam satilan urun
  food_usd INTEGER NOT NULL DEFAULT 0,              -- satilan food adedi
  food_usd_try DOUBLE PRECISION NOT NULL DEFAULT 0, -- satilan food tutari
  food_mo_try DOUBLE PRECISION NOT NULL DEFAULT 0,  -- zayi food tutari
  sold_beverage_qty INTEGER NOT NULL DEFAULT 0,     -- modifiers giren kalemler
  modifiers INTEGER NOT NULL DEFAULT 0,             -- ekstralar
  app_amount DOUBLE PRECISION NOT NULL DEFAULT 0,   -- mobil bakiye
  created_by BIGINT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  updated_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  -- Ayni magaza ve gun icin tek kayit; tekrar giris mevcut satiri gunceller.
  UNIQUE (store_id, report_date)
);
CREATE INDEX IF NOT EXISTS idx_daily_reports_store_date ON daily_reports(store_id, report_date);

-- Vardiya mudurunun girdigi masraf magaza muduru onayina takilir.
--
-- Varsayilan 'approved': bu kural gelmeden once girilen kayitlar onaylanmis
-- sayilir, aksi halde gecmis masraflar toptan bekleyene duserdi.
ALTER TABLE petty_cash_expenses ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'approved';
ALTER TABLE petty_cash_expenses ADD COLUMN IF NOT EXISTS decided_by BIGINT;
ALTER TABLE petty_cash_expenses ADD COLUMN IF NOT EXISTS decided_at TEXT;
ALTER TABLE petty_cash_expenses ADD COLUMN IF NOT EXISTS decision_note TEXT;

-- Kisit sonradan eklenir; DROP once calisir ki migration her soguk baslatmada
-- tekrar edilebilir olsun.
ALTER TABLE petty_cash_expenses DROP CONSTRAINT IF EXISTS petty_cash_status_check;
ALTER TABLE petty_cash_expenses ADD CONSTRAINT petty_cash_status_check
  CHECK (status IN ('pending', 'approved', 'rejected'));

CREATE INDEX IF NOT EXISTS idx_petty_status ON petty_cash_expenses(store_id, status);

