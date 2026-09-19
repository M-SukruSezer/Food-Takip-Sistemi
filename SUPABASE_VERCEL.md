# Supabase + Vercel canlı yayın

## Canlı adresler

| Katman   | Vercel projesi       | Adres                                                |
| -------- | -------------------- | ---------------------------------------------------- |
| Frontend | `food-takip-web`     | https://food-takip-web.vercel.app                    |
| API      | `food-takip-sistemi` | https://food-takip-sistemi.vercel.app/api            |
| Veritabanı | Supabase `Food-SKT-Takip` (`rlniektbwikjztpjazih`, `ap-south-1`) |         |

Her iki Vercel projesi de aynı GitHub deposuna (`M-SukruSezer/Food-Takip-Sistemi`) bağlıdır.

## 1. Supabase şeması

`server/supabase/schema.sql` Supabase SQL Editor'de çalıştırılır.
Şema zaten uygulanmış durumdadır; sunucu her soğuk başlatmada `initialize()`
içinde `CREATE TABLE IF NOT EXISTS` ile tekrar uygular, bu yüzden idempotenttir.

## 2. Bağlantı dizesi: doğrudan host değil, pooler

`db.<project-ref>.supabase.co` yalnızca **IPv6** üzerinden çözülür. Vercel
fonksiyonları ve çoğu yerel makine IPv4 olduğu için doğrudan host `ENETUNREACH`
verir. Supavisor pooler kullanılmalıdır:

```text
# uzun ömürlü sunucu / yerel geliştirme (session mode)
postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres

# Vercel / serverless (transaction mode)
postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:6543/postgres
```

Bu projede `server/.env` session mode (5432), Vercel production ise transaction
mode (6543) kullanır.

## 3. API projesi (`food-takip-sistemi`)

- Root Directory: `server`
- Framework: Other (`server/vercel.json` içinde `"framework": null`)
- `server/vercel.json` içindeki `routes` catch-all'ı **her** isteği
  `api/index.js` fonksiyonuna yönlendirir. Bu, sunucu kaynak dosyalarının
  statik olarak servis edilmesini de engeller.

Production ortam değişkenleri:

```env
DATABASE_URL=<Supabase transaction pooler dizesi, port 6543>
JWT_SECRET=<uzun rastgele anahtar>
SEED_DEMO_DATA=false
BOOTSTRAP_ADMIN_USERNAME=admin
BOOTSTRAP_ADMIN_PASSWORD=<en az 12 karakter>
BOOTSTRAP_ADMIN_NAME=Ana Yonetici
```

`BOOTSTRAP_ADMIN_*` yalnızca `users` tablosu boşken ilk yöneticiyi oluşturur.

Sağlık kontrolü:

```bash
curl https://food-takip-sistemi.vercel.app/api/health
```

Deploy (depo kökünden, Root Directory ayarı `server` olduğu için):

```bash
vercel deploy --prod
```

## 4. Frontend projesi (`food-takip-web`)

- Root Directory: proje kökü, `client/` dizininden deploy edilir
- Framework: Vite
- `client/vercel.json` SPA rewrite'ı tüm yolları `index.html`'e yönlendirir

Production ortam değişkeni:

```env
VITE_API_URL=https://food-takip-sistemi.vercel.app/api
```

Deploy:

```bash
cd client && vercel deploy --prod
```

`DATABASE_URL`, `JWT_SECRET` veya Supabase service-role anahtarı **asla**
frontend projesine konulmaz.
