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


-- ===========================================================================
-- PDKS (Personel Devam Kontrol Sistemi)
--
-- KVKK: biyometrik veri TUTULMAZ. Dogrulama yalnizca iki yontemle yapilir:
--   QR  -> magazadaki kioskta donen token ya da basili sabit kod
--   GPS -> cihaz konumunun magaza koordinatina uzakligi
-- Konum verisi kisisel veridir; ham koordinatlar saklanir ama
-- coords_purged_at ile saklama suresi sonunda temizlenebilir. Karar icin
-- gereken ozet (distance_m, is_valid_location) koordinat silinse de kalir.
-- ===========================================================================

-- Isyeri = magaza. Ayri bir workplaces tablosu ACILMADI: projede tum yetki
-- kapsami store_id uzerinden yurüyor (req.storeIds / storeFilter) ve
-- kullanicinin magazasi users.store_id. Ikinci bir isyeri kavrami personelin
-- magazasi ile isyerinin ayrismasina izin verip bu kapsami kirardi.
ALTER TABLE stores ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
-- Geofence yaricapi. Sehir ici GPS sapmasi 20-50 m olabildigi icin varsayilan
-- 100 m; magaza bazinda daraltilabilir.
ALTER TABLE stores ADD COLUMN IF NOT EXISTS geofence_radius_m INTEGER NOT NULL DEFAULT 100;
-- QR token uretiminde kullanilan magaza sirri. Adim 2'de HMAC ile donen token
-- uretilir; sir asla istemciye gonderilmez.
ALTER TABLE stores ADD COLUMN IF NOT EXISTS qr_secret TEXT;
-- 'rotating' = kioskta 60 sn'de bir yenilenen token (onerilen)
-- 'static'   = basili sabit kod. Fotograflanip uzaktan okutulabildigi icin
--              Adim 2'de sabit kod TEK BASINA kabul edilmeyecek, konum
--              dogrulamasiyla birlikte gecerli olacak.
ALTER TABLE stores ADD COLUMN IF NOT EXISTS qr_mode TEXT NOT NULL DEFAULT 'rotating';
-- Magaza PDKS'e dahil edilmeden hicbir davranis degismez.
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pdks_enabled INTEGER NOT NULL DEFAULT 0;

ALTER TABLE stores DROP CONSTRAINT IF EXISTS stores_qr_mode_check;
ALTER TABLE stores ADD CONSTRAINT stores_qr_mode_check
  CHECK (qr_mode IN ('rotating', 'static'));
ALTER TABLE stores DROP CONSTRAINT IF EXISTS stores_geofence_radius_check;
ALTER TABLE stores ADD CONSTRAINT stores_geofence_radius_check
  CHECK (geofence_radius_m BETWEEN 20 AND 5000);

-- Personelin PDKS profili: izin/avans hakki ve hafta tatili.
CREATE TABLE IF NOT EXISTS pdks_profiles (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  hired_at TEXT,                                        -- YYYY-MM-DD
  -- 4857 sayili Is Kanunu'nda 1-5 yil arasi yillik izin 14 gun; varsayilan bu.
  annual_leave_days DOUBLE PRECISION NOT NULL DEFAULT 14,
  monthly_advance_limit DOUBLE PRECISION NOT NULL DEFAULT 0,
  -- Hafta tatili gunleri, users.permissions ile ayni desende JSON metin.
  -- 0 = Pazar ... 6 = Cumartesi. Ornek: '[0]' ya da '[0,6]'.
  weekly_off_days TEXT NOT NULL DEFAULT '[0]',
  updated_by BIGINT,
  updated_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

-- Vardiya tanimi. store_id NULL ise tum magazalarda kullanilabilir sablon.
CREATE TABLE IF NOT EXISTS shifts (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT REFERENCES stores(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  -- Duvar saati, 'HH:MM'. Saat dilimi tasimaz: 08:00 vardiyasi her gun 08:00.
  -- Bu yuzden TEXT; ISO zaman damgasi kullanmak yaz saati kaymasi yaratirdi.
  start_time TEXT NOT NULL,
  -- end_time <= start_time ise vardiya gece yarisini gecer (22:00 -> 06:00).
  end_time TEXT NOT NULL,
  break_duration_minutes INTEGER NOT NULL DEFAULT 0,
  -- 08:00 vardiyasinda 10 dk tolerans: 08:10'a kadar gec sayilmaz.
  late_tolerance_minutes INTEGER NOT NULL DEFAULT 0,
  early_leave_tolerance_minutes INTEGER NOT NULL DEFAULT 0,
  -- Vardiya bitisinden bu kadar sonrasi fazla mesai sayilir; kisa
  -- sarkmalar mesaiye yazilmasin.
  overtime_starts_after_minutes INTEGER NOT NULL DEFAULT 15,
  active INTEGER NOT NULL DEFAULT 1,
  created_by BIGINT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

ALTER TABLE shifts DROP CONSTRAINT IF EXISTS shifts_time_format_check;
ALTER TABLE shifts ADD CONSTRAINT shifts_time_format_check
  CHECK (start_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     AND end_time   ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
ALTER TABLE shifts DROP CONSTRAINT IF EXISTS shifts_minutes_check;
ALTER TABLE shifts ADD CONSTRAINT shifts_minutes_check
  CHECK (break_duration_minutes BETWEEN 0 AND 480
     AND late_tolerance_minutes BETWEEN 0 AND 120
     AND early_leave_tolerance_minutes BETWEEN 0 AND 120
     AND overtime_starts_after_minutes BETWEEN 0 AND 120);

-- Personel-gun vardiya atamasi. shift_id NULL + is_day_off=1 hafta tatili.
CREATE TABLE IF NOT EXISTS user_shifts (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shift_id BIGINT REFERENCES shifts(id) ON DELETE RESTRICT,
  work_date TEXT NOT NULL,                              -- YYYY-MM-DD
  is_day_off INTEGER NOT NULL DEFAULT 0,
  note TEXT,
  assigned_by BIGINT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  -- Ayni gune ayni vardiya iki kez atanamaz. Bolunmus vardiyaya (sabah +
  -- aksam) izin verilir: farkli shift_id ile ayni gun eklenebilir.
  UNIQUE (user_id, work_date, shift_id)
);

ALTER TABLE user_shifts DROP CONSTRAINT IF EXISTS user_shifts_date_format_check;
ALTER TABLE user_shifts ADD CONSTRAINT user_shifts_date_format_check
  CHECK (work_date ~ '^\d{4}-\d{2}-\d{2}$');
-- Tatil satirinda vardiya olmaz, vardiya satirinda tatil olmaz.
ALTER TABLE user_shifts DROP CONSTRAINT IF EXISTS user_shifts_dayoff_check;
ALTER TABLE user_shifts ADD CONSTRAINT user_shifts_dayoff_check
  CHECK ((is_day_off = 1 AND shift_id IS NULL) OR (is_day_off = 0 AND shift_id IS NOT NULL));
-- UNIQUE kisiti NULL'lari tekil saymadigi icin tatil satiri ayri indeksle
-- tekillestirilir; aksi halde ayni gune iki tatil yazilabiliyor.
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_shifts_dayoff
  ON user_shifts(user_id, work_date) WHERE shift_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_shifts_user_date ON user_shifts(user_id, work_date);
CREATE INDEX IF NOT EXISTS idx_user_shifts_date ON user_shifts(work_date);

-- Giris/cikis kaydi.
CREATE TABLE IF NOT EXISTS attendance_logs (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  store_id BIGINT NOT NULL REFERENCES stores(id),
  type TEXT NOT NULL,                                   -- GIRIS | CIKIS
  method TEXT NOT NULL,                                 -- QR | GPS
  occurred_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  -- Kaydin yazildigi IS GUNU. Gece vardiyasinda cikis ertesi takvim gunune
  -- duser; puantaj bu kolona gore grupladigi icin vardiyanin basladigi gun
  -- yazilir, occurred_at'in tarihi degil.
  work_date TEXT NOT NULL,
  -- Konum yalnizca GPS yonteminde dolu; QR'da sorulmaz (KVKK: amacla sinirli).
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  -- Cihazin bildirdigi dogruluk yaricapi. Buyuk accuracy ile gelen kayit
  -- yaricap icinde gorunse de guvenilir degil; Adim 2'de esik uygulanir.
  accuracy_m DOUBLE PRECISION,
  -- Haversine ile hesaplanan magazaya uzaklik. Koordinat KVKK saklama suresi
  -- sonunda silinse bile karar bu ozetle denetlenebilir kalir.
  distance_m DOUBLE PRECISION,
  is_valid_location INTEGER,                             -- NULL = konum sorulmadi
  -- Android/iOS sahte konum bayragi. Web Geolocation API bunu vermedigi icin
  -- NULL olabilir: "bilinmiyor" ile "sahte degil" ayri tutulur.
  is_mocked INTEGER,
  -- Okutulan QR token'inin ozeti. Ayni token'in ikinci kez kullanilmasini
  -- engellemek icin saklanir; token'in kendisi saklanmaz.
  qr_token_hash TEXT,
  device_label TEXT,
  note TEXT,
  -- Kiosk ya da yonetici okuttuysa islemi yapan kullanici; personelin kendi
  -- cihazindan yaptigi kayitta user_id ile ayni olur.
  created_by BIGINT,
  -- KVKK saklama suresi sonunda ham koordinatlar bosaltilinca damgalanir.
  coords_purged_at TEXT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

ALTER TABLE attendance_logs DROP CONSTRAINT IF EXISTS attendance_logs_type_check;
ALTER TABLE attendance_logs ADD CONSTRAINT attendance_logs_type_check
  CHECK (type IN ('GIRIS', 'CIKIS'));
-- Yalnizca iki yontem. Biyometrik ya da elle giris bu kisittan gecmez.
ALTER TABLE attendance_logs DROP CONSTRAINT IF EXISTS attendance_logs_method_check;
ALTER TABLE attendance_logs ADD CONSTRAINT attendance_logs_method_check
  CHECK (method IN ('QR', 'GPS'));
-- GPS yonteminde koordinat ve gecerlilik zorunlu; aksi halde dogrulanmamis
-- bir kayit GPS gibi gorunebilir.
ALTER TABLE attendance_logs DROP CONSTRAINT IF EXISTS attendance_logs_gps_check;
ALTER TABLE attendance_logs ADD CONSTRAINT attendance_logs_gps_check
  CHECK (
    method <> 'GPS'
    OR (is_valid_location IS NOT NULL
        AND (coords_purged_at IS NOT NULL OR (latitude IS NOT NULL AND longitude IS NOT NULL)))
  );
ALTER TABLE attendance_logs DROP CONSTRAINT IF EXISTS attendance_logs_date_format_check;
ALTER TABLE attendance_logs ADD CONSTRAINT attendance_logs_date_format_check
  CHECK (work_date ~ '^\d{4}-\d{2}-\d{2}$');

CREATE INDEX IF NOT EXISTS idx_attendance_user_date ON attendance_logs(user_id, work_date);
CREATE INDEX IF NOT EXISTS idx_attendance_store_time ON attendance_logs(store_id, occurred_at);
-- "Su an kimler iste" sorgusu: son kaydin turune bakar.
CREATE INDEX IF NOT EXISTS idx_attendance_user_time ON attendance_logs(user_id, occurred_at DESC);
-- Ayni personel ayni token'i ikinci kez kullanamaz.
--
-- Tekillik KISI BASINA: kioskta donen token 60 sn boyunca ayni oldugu icin
-- global tekillik o dakika icinde giris yapan ikinci personeli reddederdi.
-- Sabit basili kodda token hash'i hic yazilmaz (her zaman ayni olurdu);
-- orada tekrar korumasi konum dogrulamasindan gelir.
DROP INDEX IF EXISTS idx_attendance_qr_token;
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_qr_token_user
  ON attendance_logs(user_id, qr_token_hash) WHERE qr_token_hash IS NOT NULL;
-- KVKK temizligi: suresi gecmis, koordinati hala dolu kayitlari bulur.
CREATE INDEX IF NOT EXISTS idx_attendance_purge
  ON attendance_logs(occurred_at) WHERE coords_purged_at IS NULL AND latitude IS NOT NULL;

-- Izin / saatlik izin / avans talepleri.
--
-- Ad bilerek 'requests' degil: bu veritabaninda transfer_approvals ve
-- petty_cash onay akislari da var, hangi talep oldugu adindan anlasilmali.
CREATE TABLE IF NOT EXISTS personnel_requests (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  store_id BIGINT NOT NULL REFERENCES stores(id),
  type TEXT NOT NULL,                                   -- IZIN | SAATLIK_IZIN | AVANS
  -- IZIN'de YYYY-MM-DD, SAATLIK_IZIN'de ISO zaman damgasi. AVANS'ta bos.
  start_at TEXT,
  end_at TEXT,
  -- Talep aninda hesaplanip saklanir: izin hakki dusumu, kural sonradan
  -- degisse de gecmis talebin degeri kaymasin.
  days DOUBLE PRECISION,
  hours DOUBLE PRECISION,
  amount DOUBLE PRECISION,                              -- AVANS tutari
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  manager_id BIGINT REFERENCES users(id),
  decided_at TEXT,
  decision_note TEXT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

ALTER TABLE personnel_requests DROP CONSTRAINT IF EXISTS personnel_requests_type_check;
ALTER TABLE personnel_requests ADD CONSTRAINT personnel_requests_type_check
  CHECK (type IN ('IZIN', 'SAATLIK_IZIN', 'AVANS'));
ALTER TABLE personnel_requests DROP CONSTRAINT IF EXISTS personnel_requests_status_check;
ALTER TABLE personnel_requests ADD CONSTRAINT personnel_requests_status_check
  CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'));
-- Tur ile dolu alanlar tutarli olmali: avansta tutar, izinde tarih.
ALTER TABLE personnel_requests DROP CONSTRAINT IF EXISTS personnel_requests_shape_check;
ALTER TABLE personnel_requests ADD CONSTRAINT personnel_requests_shape_check
  CHECK (
    (type = 'AVANS' AND amount IS NOT NULL AND amount > 0)
    OR (type IN ('IZIN', 'SAATLIK_IZIN') AND start_at IS NOT NULL AND end_at IS NOT NULL)
  );
-- Karar verilmis talepte karar veren ve zamani bulunmali.
ALTER TABLE personnel_requests DROP CONSTRAINT IF EXISTS personnel_requests_decision_check;
ALTER TABLE personnel_requests ADD CONSTRAINT personnel_requests_decision_check
  CHECK (status = 'PENDING' OR status = 'CANCELLED' OR (manager_id IS NOT NULL AND decided_at IS NOT NULL));

CREATE INDEX IF NOT EXISTS idx_personnel_requests_user ON personnel_requests(user_id, created_at DESC);
-- Yoneticinin onay kuyrugu.
CREATE INDEX IF NOT EXISTS idx_personnel_requests_pending
  ON personnel_requests(store_id) WHERE status = 'PENDING';

-- Resmi tatiller.
--
-- Yillik izin calisma gunu uzerinden sayilir: hafta tatili ve resmi tatil
-- dusulur (4857/m.56). Onceki surumde resmi tatil dusulmuyordu ve kullaniciya
-- bu bildiriliyordu; artik bu tablodan okunuyor.
--
-- Dini bayramlar her yil kaydigi icin TOHUMLANMIYOR: tarih uydurmak yanlis
-- izin hesabi uretir. Sabit milli bayramlar /pdks/holidays/seed ile yilbasina
-- eklenir, dini bayramlar elle girilir.
CREATE TABLE IF NOT EXISTS public_holidays (
  id BIGSERIAL PRIMARY KEY,
  holiday_date TEXT NOT NULL,                           -- YYYY-MM-DD
  name TEXT NOT NULL,
  -- Arefe gunleri yarim tatil: izin hesabinda 0.5 gun sayilir.
  is_half_day INTEGER NOT NULL DEFAULT 0,
  -- NULL = tum magazalar. Magazaya ozel tatil (yerel kurtulus gunu) icin dolu.
  store_id BIGINT REFERENCES stores(id) ON DELETE CASCADE,
  created_by BIGINT,
  created_at TEXT NOT NULL DEFAULT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
);

ALTER TABLE public_holidays DROP CONSTRAINT IF EXISTS public_holidays_date_check;
ALTER TABLE public_holidays ADD CONSTRAINT public_holidays_date_check
  CHECK (holiday_date ~ '^\d{4}-\d{2}-\d{2}$');

-- Ayni gune ayni kapsamda iki kayit olmasin. NULL'lar tekil sayilmadigi icin
-- genel ve magazaya ozel tatiller ayri indekslerle tekillestirilir.
CREATE UNIQUE INDEX IF NOT EXISTS idx_holidays_global
  ON public_holidays(holiday_date) WHERE store_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_holidays_store
  ON public_holidays(store_id, holiday_date) WHERE store_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_holidays_date ON public_holidays(holiday_date);
