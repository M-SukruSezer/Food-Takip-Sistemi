import { useCallback, useEffect, useState } from 'react';
import {
  Clock, LogIn, LogOut, CalendarDays,
  Wallet, Plus, ScanLine, RefreshCw, Coffee, Play, AlertTriangle,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, toast } from '../components/ui';
import QrScanner from '../components/pdks/QrScanner';
import { TalepModal, TalepListesi } from '../components/pdks/Talepler';
import { fmtDate, fmtDateTime, errorMessage } from '../format';

// Personel PDKS ekrani: durum, QR ile giris/cikis, bakiye, talepler, takvim.
//
// TEK ISLEM YOLU QR — ama QR tek basina yetmiyor. Kodun IS YERINDE
// okutuldugu konumla dogrulaniyor, sahte konum reddediliyor.
//
// KVKK: konum yalnizca okutma aninda aliniyor, arka planda izleme yok.

const LOG_ETIKET = {
  GIRIS: ['Giriş', 'sold'],
  CIKIS: ['Çıkış', 'discarded'],
  MOLA_BASLA: ['Mola başladı', 'warning'],
  MOLA_BITIR: ['Mola bitti', 'info'],
};

/// Bugunku molalar: MOLA_BASLA acar, MOLA_BITIR ya da CIKIS kapatir.
/// Kapanmamis mola "suruyor" olarak doner.
export function molaParcalari(logs, simdi = new Date()) {
  const sirali = [...logs].sort((a, b) => String(a.occurred_at).localeCompare(String(b.occurred_at)));
  const out = [];
  let acik = null;
  for (const l of sirali) {
    if (l.type === 'MOLA_BASLA') acik = new Date(l.occurred_at);
    else if ((l.type === 'MOLA_BITIR' || l.type === 'CIKIS') && acik) {
      out.push({ bas: acik, bit: new Date(l.occurred_at) });
      acik = null;
    }
  }
  if (acik) out.push({ bas: acik, bit: null });
  return out.map((m) => ({
    ...m,
    dakika: Math.max(0, Math.floor(((m.bit || simdi) - m.bas) / 60000)),
  }));
}
const saatDk = (d) => d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });

export default function Pdks() {
  const { user } = useAuth();
  const [durum, setDurum] = useState(null);
  const [bakiye, setBakiye] = useState(null);
  const [talepler, setTalepler] = useState([]);
  const [takvim, setTakvim] = useState([]);
  const [tatiller, setTatiller] = useState([]);
  const [ay, setAy] = useState(() => new Date().toISOString().slice(0, 7));
  const [reload, setReload] = useState(0);
  const [hata, setHata] = useState('');
  const [mesgul, setMesgul] = useState(false);
  const [okuyucu, setOkuyucu] = useState(null);
  const [talepForm, setTalepForm] = useState(false);

  const yukle = useCallback(() => {
    api.get('/pdks/me').then((r) => { setDurum(r.data); setHata(''); })
      .catch((e) => setHata(errorMessage(e)));
    api.get('/pdks/requests/balances', { silent: true }).then((r) => setBakiye(r.data)).catch(() => {});
    api.get('/pdks/requests', { silent: true }).then((r) => setTalepler(r.data)).catch(() => {});
  }, []);

  useEffect(() => { yukle(); }, [yukle, reload]);

  useEffect(() => {
    const son = new Date(`${ay}-01T00:00:00Z`);
    son.setUTCMonth(son.getUTCMonth() + 1);
    son.setUTCDate(0);
    const bitis = son.toISOString().slice(0, 10);
    api.get(`/pdks/assignments?from=${ay}-01&to=${bitis}`, { silent: true })
      .then((r) => setTakvim(r.data)).catch(() => {});
    // Resmi tatiller takvimde isaretlenir: personel izin planlarken hangi
    // gunun tatil oldugunu gormeli.
    api.get(`/pdks/holidays?from=${ay}-01&to=${bitis}`, { silent: true })
      .then((r) => setTatiller(r.data)).catch(() => {});
  }, [ay, reload]);

// Tarayicida cihaz butunlugu KONTROL EDILEMEZ: root/emulator tespiti icin bir
// web API'si yok. "Temiz" demek yerine kontrol edilemedigi bildiriliyor;
// sunucu kaydi "unverified" bayragiyla isaretliyor ve yonetici hangi
// girislerin cihaz dogrulamasindan gectigini ayirt edebiliyor.
const WEB_INTEGRITY = { checked: false };

// Dort adimin uc noktalari ve bildirim metinleri tek yerde: iki islem
// fonksiyonu da buradan besleniyor, metinler ayrismasin.
const ADIM = {
  GIRIS: { yol: 'check-in', mesaj: 'Giriş kaydedildi' },
  CIKIS: { yol: 'check-out', mesaj: 'Çıkış kaydedildi' },
  MOLA_BASLA: { yol: 'break-start', mesaj: 'Mola başladı' },
  MOLA_BITIR: { yol: 'break-end', mesaj: 'Mola bitti' },
};

  /// Cihazin anlik konumu. Yalnizca QR okutulurken cagriliyor.
  ///
  /// Tarayici Geolocation API'si sahte konum bayragi VERMIYOR; sunucu bu
  /// yuzden konum atlamasi (teleport) kontrolu de yapiyor. Sahte konum
  /// tespiti mobil uygulamada (Android: isFromMockProvider).
  function konumAl() {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) {
        reject(new Error('Bu cihaz konum desteklemiyor'));
        return;
      }
      navigator.geolocation.getCurrentPosition(
        (p) => resolve({
          latitude: p.coords.latitude,
          longitude: p.coords.longitude,
          accuracy: p.coords.accuracy,
        }),
        (e) => reject(new Error(
          e.code === 1 ? 'Konum izni verilmedi. QR kodun iş yerinde okutulduğu konumla doğrulanıyor.'
            : e.code === 3 ? 'Konum alınamadı, açık alanda tekrar deneyin'
            : 'Konum alınamadı'
        )),
        // Onbellekteki eski konum kabul edilmez: okutma anindaki konum gerekir.
        { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
      );
    });
  }

  /// Tek islem yolu: QR okut + konum dogrula.
  async function qrIslem(tip, token) {
    setOkuyucu(null);
    setMesgul(true);
    try {
      // Konum ZORUNLU: alinamazsa istek hic gonderilmiyor, kullaniciya
      // sebebi soyleniyor. Sunucuya gidip "konum doğrulanamadı" almak
      // yerine burada net mesaj veriliyor.
      const konum = await konumAl();
      await api.post(`/pdks/${ADIM[tip].yol}`,
        {
          method: 'QR',
          // 6 haneli rakam: PIN Dogrulama kodu; aksi halde QR icerigi.
          ...(/^\d{6}$/.test(token) ? { manager_pin: token } : { qr_token: token }),
          ...konum,
          device_integrity: WEB_INTEGRITY,
        },
        { noToast: true, busyMessage: 'Konum doğrulanıyor...' });
      toast(ADIM[tip].mesaj);
      setReload((n) => n + 1);
    } catch (e) {
      toast(errorMessage(e) || e.message);
    } finally {
      setMesgul(false);
    }
  }

  if (hata && !durum) {
    return (
      <div className="page-shell">
        <div className="alert error">{hata}</div>
      </div>
    );
  }
  if (!durum) return null;

  const iceride = durum.is_inside;
  const molada = durum.on_break;
  // Sunucu sonraki gecerli adimlari kendisi bildiriyor; kurali burada tekrar
  // yazmak iki tarafin ayrismasi demekti.
  const izin = durum.can || {};
  const magaza = durum.store || {};
  const pdksAcik = magaza.pdks_enabled;
  // Islem icin IKI ETKEN de hazir olmali: QR sirri ve magaza konumu.
  const hazir = pdksAcik && magaza.has_qr && magaza.has_location;
  // Operasyon alanindan buraya yonlendirildik mi (sunucu SHIFT_REQUIRED dedi).
  const mesaiIstendi = new URLSearchParams(window.location.search).get('shift') === '1';

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Clock size={20} /> Devam Takibi</h2>
        <span className={`badge ${molada ? 'warning' : iceride ? 'sold' : 'discarded'}`}>
          {molada ? 'Moladasınız' : iceride ? 'İş yerindesiniz' : 'İş yerinde değilsiniz'}
        </span>
      </div>

      {!pdksAcik && (
        <div className="alert warning">
          Bu mağazada devam takibi henüz açılmamış. Yöneticinizle görüşün.
        </div>
      )}

      {/* Operasyon alanindan yonlendirildiyse sebebi yaziliyor: personel bos
          bir ekranla kalip ne yapmasi gerektigini bilemesin. */}
      {mesaiIstendi && !iceride && (
        <div className="alert warning" style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <AlertTriangle size={18} />
          <span>Ürün, satış ve rapor bölümlerine girmek için önce işe giriş yapmalısınız.</span>
        </div>
      )}

      {/* --- Giris / cikis --- */}
      <section className="surface-panel">
        <div className="pdks-status">
          <div>
            <span className="muted">{durum.work_date} · {magaza.name || '-'}</span>
            {iceride && (
              <p className="pdks-since">
                {fmtDateTime(durum.open_since)} itibarıyla giriş yapıldı
              </p>
            )}
            {molada && (
              <p className="pdks-since" style={{ color: 'var(--warning-text)' }}>
                {fmtDateTime(durum.break_since)} itibarıyla molada
              </p>
            )}
            {durum.break_minutes_today > 0 && (
              <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '2px 0 0' }}>
                Bugün toplam mola: {durum.break_minutes_today} dk
              </p>
            )}
          </div>
        </div>

        {/* Dort adimin da TEK yolu QR okutmak. Her dugme okuyucuyu kendi
            adimiyla aciyor: "QR okut" deyip sonra ne yapildigini tahmin
            ettirmek yerine niyet dugmede belli. */}
        <div className="pdks-actions">
          <button
            className={`btn ${izin.check_in ? 'btn-primary' : 'btn-secondary'} btn-lg`}
            disabled={mesgul || !hazir || !izin.check_in}
            onClick={() => setOkuyucu('GIRIS')}
          >
            <LogIn size={18} /> QR ile İşe Başla
          </button>
          <button
            className={`btn ${izin.check_out ? 'btn-primary' : 'btn-secondary'} btn-lg`}
            disabled={mesgul || !hazir || !izin.check_out}
            onClick={() => setOkuyucu('CIKIS')}
          >
            <LogOut size={18} /> QR ile İşi Bitir
          </button>
        </div>

        {/* Mola adimlari. Molada cikis yapilamiyor: sunucu da engelliyor,
            dugme de kapali kaliyor ki sebebi denemeden anlasilsin. */}
        <div className="pdks-actions">
          <button
            className={`btn ${izin.break_start ? 'btn-primary' : 'btn-secondary'}`}
            disabled={mesgul || !hazir || !izin.break_start}
            onClick={() => setOkuyucu('MOLA_BASLA')}
          >
            <Coffee size={16} /> QR ile Molaya Çık
          </button>
          <button
            className={`btn ${izin.break_end ? 'btn-primary' : 'btn-secondary'}`}
            disabled={mesgul || !hazir || !izin.break_end}
            onClick={() => setOkuyucu('MOLA_BITIR')}
          >
            <Play size={16} /> QR ile Moladan Dön
          </button>
        </div>

        {pdksAcik && (!magaza.has_qr || !magaza.has_location) && (
          <div className="alert warning" style={{ marginTop: 8 }}>
            Bu mağazada {!magaza.has_qr ? 'QR kod' : 'mağaza konumu'} tanımlı değil.
            Giriş/çıkış yapılamaz, yöneticinizle görüşün.
          </div>
        )}
        <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '8px 0 0', display: 'flex', gap: 6 }}>
          <ScanLine size={14} />
          Giriş, çıkış ve mola işlemleri iş yerindeki QR kod okutularak yapılır.
          Kodu okuttuğunuz anda konumunuz alınır ve
          {magaza.has_location ? ` ${magaza.geofence_radius_m} m ` : ' '}
          iş yeri yarıçapıyla karşılaştırılır. Arka planda konum izlenmez.
        </p>
      </section>

      {/* --- Bugunun vardiyasi ve kayitlari --- */}
      <section className="surface-panel">
        <h3 style={{ margin: '0 0 8px', fontSize: 'var(--fs-base)' }}>Bugün</h3>
        {durum.shifts.length === 0 ? (
          <p className="muted" style={{ fontSize: 'var(--fs-body)', margin: 0 }}>Bugün için vardiya atanmamış.</p>
        ) : (
          <div className="chip-row" style={{ marginBottom: 10 }}>
            {durum.shifts.map((s, i) => (
              <span className="chip" key={i}>
                {s.is_day_off ? 'Hafta tatili'
                  : `${s.name} · ${s.start_time}-${s.end_time}`
                    + (s.late_tolerance_minutes ? ` (${s.late_tolerance_minutes} dk tolerans)` : '')}
              </span>
            ))}
          </div>
        )}
        {durum.logs.length === 0 ? (
          <p className="muted" style={{ fontSize: 'var(--fs-body)', margin: 0 }}>Bugün kayıt yok.</p>
        ) : (
          <ul className="pdks-log-list">
            {durum.logs.map((l) => (
              <li key={l.id}>
                <span className={`badge ${(LOG_ETIKET[l.type] || [])[1] || 'discarded'}`}>
                  {(LOG_ETIKET[l.type] || [l.type])[0]}
                </span>
                <strong>{fmtDateTime(l.occurred_at)}</strong>
                <span className="muted">{l.method}</span>
                {l.distance_m !== null && l.distance_m !== undefined && (
                  <span className="muted">{Math.round(l.distance_m)} m</span>
                )}
              </li>
            ))}
          </ul>
        )}
        <MolaHaklari vardiyalar={durum.shifts} logs={durum.logs} />
      </section>

      {/* --- Bakiye --- */}
      {bakiye && (
        <section className="surface-panel">
          <div className="mo-head">
            <h3><Wallet size={18} /> İzin Durumu</h3>
            <span className="muted">
              İzin yılı: {fmtDate(bakiye.leave_year.from)} – {fmtDate(bakiye.leave_year.to)}
            </span>
          </div>
          <div className="mo-figures">
            <div className="mo-figure">
              <span>Kalan yıllık izin</span>
              <strong className="text-ok">{bakiye.leave.remaining_days} gün</strong>
            </div>
            <div className="mo-figure">
              <span>Kullanılan</span>
              <strong>{bakiye.leave.used_days} gün</strong>
            </div>
            <div className="mo-figure">
              <span>Onay bekleyen</span>
              <strong className="text-warning">{bakiye.leave.pending_days} gün</strong>
            </div>
          </div>
          {bakiye.hourly_leave.used_hours > 0 && (
            <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '8px 0 0' }}>
              Bu ay {bakiye.hourly_leave.used_hours} saat saatlik izin kullanıldı
              (yıllık izin gününden düşülmez).
            </p>
          )}
          {bakiye.notes.map((n, i) => (
            <p className="muted" key={i} style={{ fontSize: 'var(--fs-caption)', margin: '4px 0 0' }}>{n}</p>
          ))}
        </section>
      )}

      {/* --- Talepler --- */}
      <section className="surface-panel">
        <div className="mo-head">
          <h3>Taleplerim</h3>
          <button className="btn btn-sm btn-primary" onClick={() => setTalepForm(true)}>
            <Plus size={14} /> Yeni Talep
          </button>
        </div>
        <TalepListesi talepler={talepler} user={user} onChange={() => setReload((n) => n + 1)} />
      </section>

      {/* --- Aylik vardiya takvimi --- */}
      <section className="surface-panel">
        <div className="mo-head">
          <h3><CalendarDays size={18} /> Vardiya Takvimi</h3>
          <input type="month" value={ay} onChange={(e) => setAy(e.target.value)} />
        </div>
        <Takvim ay={ay} atamalar={takvim} tatiller={tatiller} />
      </section>


      {okuyucu && (
        <Modal title={`QR ile ${okuyucu === 'GIRIS' ? 'Giriş' : 'Çıkış'}`} onClose={() => setOkuyucu(null)}>
          <QrScanner onResult={(token) => qrIslem(okuyucu, token)} onClose={() => setOkuyucu(null)} />
        </Modal>
      )}

      {talepForm && (
        <TalepModal
          bakiye={bakiye}
          onClose={() => setTalepForm(false)}
          onDone={() => { setTalepForm(false); setReload((n) => n + 1); }}
        />
      )}
    </div>
  );
}

/// Aylik vardiya takvimi. Pazartesi ile baslar (TR takvim alisligi).
function Takvim({ ay, atamalar, tatiller = [] }) {
  const [y, m] = ay.split('-').map(Number);
  const ilk = new Date(Date.UTC(y, m - 1, 1));
  const gunSayisi = new Date(Date.UTC(y, m, 0)).getUTCDate();
  // getUTCDay: 0=Pazar. Pazartesi basli izgaraya cevir.
  const bosluk = (ilk.getUTCDay() + 6) % 7;

  const gunler = new Map();
  for (const a of atamalar) {
    if (!gunler.has(a.work_date)) gunler.set(a.work_date, []);
    gunler.get(a.work_date).push(a);
  }
  // Magazaya ozel tatil geneli gecersiz kilar (sunucu tarafiyla ayni kural).
  const tatilGunleri = new Map();
  for (const h of tatiller) {
    const mevcut = tatilGunleri.get(h.holiday_date);
    if (mevcut && mevcut.store_id !== null && h.store_id === null) continue;
    tatilGunleri.set(h.holiday_date, h);
  }

  const hucreler = [];
  for (let i = 0; i < bosluk; i++) hucreler.push(<div className="cal-cell empty" key={`b${i}`} />);
  for (let d = 1; d <= gunSayisi; d++) {
    const tarih = `${ay}-${String(d).padStart(2, '0')}`;
    const liste = gunler.get(tarih) || [];
    const haftaTatili = liste.some((a) => a.is_day_off);
    const resmi = tatilGunleri.get(tarih);
    const sinif = resmi ? 'holiday' : haftaTatili ? 'off' : liste.length ? 'on' : '';
    hucreler.push(
      <div className={`cal-cell ${sinif}`} key={tarih} title={resmi ? resmi.name : undefined}>
        <span className="cal-day">{d}</span>
        {resmi && (
          <em className="cal-holiday">
            {resmi.name}{resmi.is_half_day ? ' (½)' : ''}
          </em>
        )}
        {!resmi && haftaTatili && <em>Tatil</em>}
        {!resmi && !haftaTatili && liste.map((a, i) => (
          <em key={i}>{a.start_time}–{a.end_time}</em>
        ))}
      </div>
    );
  }

  return (
    <>
      <div className="cal-head">
        {['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'].map((g) => <span key={g}>{g}</span>)}
      </div>
      <div className="cal-grid">{hucreler}</div>
      {atamalar.length === 0 && (
        <p className="muted" style={{ fontSize: 'var(--fs-body)', margin: '10px 0 0' }}>
          Bu ay için vardiya atanmamış.
        </p>
      )}
      {tatiller.length > 0 && (
        <p className="muted" style={{ fontSize: 'var(--fs-caption)', margin: '8px 0 0' }}>
          Kırmızı çerçeveli günler resmi tatil; yıllık izin hakkınızdan düşülmez.
        </p>
      )}
    </>
  );
}

/// Mola haklari ve kullanimi: hak bugunku vardiyanin tanimli mola suresi,
/// kullanim bugunun gercek mola kayitlarindan hesaplanir.
function MolaHaklari({ vardiyalar, logs }) {
  const hak = vardiyalar
    .filter((v) => !v.is_day_off)
    .reduce((a, v) => a + (Number(v.break_duration_minutes) || 0), 0);
  const molalar = molaParcalari(logs);
  const kullanilan = molalar.reduce((a, m) => a + m.dakika, 0);
  const kalan = Math.max(0, hak - kullanilan);
  return (
    <div className="mola-haklari">
      <div className="mo-head">
        <h3 style={{ margin: 0, fontSize: 'var(--fs-base)' }}><Coffee size={16} /> Mola Hakları ve Kullanımı</h3>
        <span className="muted">{hak > 0 ? `${hak} dk hak` : 'Hak tanımsız'}</span>
      </div>
      <div className="grid stats">
        <div className="stat stat-card"><div className="label">Toplam Hak</div><div className="value">{hak > 0 ? `${hak} dk` : '—'}</div></div>
        <div className="stat stat-card"><div className="label">Kullanılan</div><div className="value">{kullanilan} dk</div></div>
        <div className="stat stat-card"><div className="label">Kalan</div><div className="value">{hak > 0 ? `${kalan} dk` : '—'}</div></div>
      </div>
      {molalar.length === 0 ? (
        <p className="muted" style={{ fontSize: 'var(--fs-body)', margin: '8px 0 0' }}>Bugün henüz mola kullanılmadı.</p>
      ) : (
        <ul className="pdks-log-list">
          {molalar.map((m, i) => (
            <li key={i}>
              <strong>{i + 1}. Mola</strong>
              <span>{saatDk(m.bas)} – {m.bit ? saatDk(m.bit) : '…'}</span>
              <span className="muted">{m.dakika} dk</span>
              <span className={`badge ${m.bit ? 'sold' : 'warning'}`}>{m.bit ? 'Tamamlandı' : 'Sürüyor'}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
