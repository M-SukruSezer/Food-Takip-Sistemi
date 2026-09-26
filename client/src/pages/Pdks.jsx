import { useCallback, useEffect, useState } from 'react';
import {
  Clock, MapPin, QrCode as QrIcon, LogIn, LogOut, CalendarDays,
  Wallet, Plus, ScanLine, RefreshCw,
} from 'lucide-react';
import api from '../api';
import { Modal, toast } from '../components/ui';
import QrCode from '../components/pdks/QrCode';
import QrScanner from '../components/pdks/QrScanner';
import { fmtDate, fmtDateTime, fmtMoney, errorMessage } from '../format';

// Personel PDKS ekrani: durum, giris/cikis, QR, bakiye, talepler, takvim.
//
// KVKK: konum yalnizca GPS ile islem yapilirken ve o an aliniyor; arka planda
// izleme yok. Kullaniciya da bu yaziliyor.

const TALEP_ETIKET = { IZIN: 'Yıllık İzin', SAATLIK_IZIN: 'Saatlik İzin', AVANS: 'Avans' };
const DURUM_ETIKET = { PENDING: 'Bekliyor', APPROVED: 'Onaylandı', REJECTED: 'Reddedildi', CANCELLED: 'İptal' };
const DURUM_SINIF = { PENDING: 'warning', APPROVED: 'sold', REJECTED: 'critical', CANCELLED: 'discarded' };

export default function Pdks() {
  const [durum, setDurum] = useState(null);
  const [bakiye, setBakiye] = useState(null);
  const [talepler, setTalepler] = useState([]);
  const [takvim, setTakvim] = useState([]);
  const [tatiller, setTatiller] = useState([]);
  const [ay, setAy] = useState(() => new Date().toISOString().slice(0, 7));
  const [reload, setReload] = useState(0);
  const [hata, setHata] = useState('');
  const [mesgul, setMesgul] = useState(false);
  const [qrGoster, setQrGoster] = useState(null);
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

  /// Cihazin anlik konumunu alir.
  ///
  /// Web Geolocation API sahte konum bayragi VERMIYOR; sunucu bu yuzden
  /// konum atlamasi kontrolu de yapiyor. Bunu kullaniciya soylemiyoruz ama
  /// davranisi biliyoruz.
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
          e.code === 1 ? 'Konum izni verilmedi'
            : e.code === 3 ? 'Konum alınamadı, açık alanda tekrar deneyin'
            : 'Konum alınamadı'
        )),
        // Onbellekteki eski konum kabul edilmez: giris anindaki konum gerekir.
        { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
      );
    });
  }

// Tarayicida cihaz butunlugu KONTROL EDILEMEZ: ne sahte konum bayragi, ne
// root, ne emulator tespiti icin bir web API'si var. Bu yuzden "temiz"
// gondermek yerine kontrol edilemedigi bildiriliyor; sunucu kaydi
// "unverified" bayragiyla isaretliyor ve yonetici hangi girislerin cihaz
// dogrulamasindan gectigini ayirt edebiliyor.
//
// Sahte konum tespiti mobil uygulamada yapiliyor (Android: isFromMockProvider).
// Tarayici icin geriye kalan savunma sunucu tarafinda: geofence ve onceki
// kayitla arasindaki hiz (teleport) kontrolu.
const WEB_INTEGRITY = { checked: false };

  async function gpsIslem(tip) {
    setMesgul(true);
    try {
      const konum = await konumAl();
      await api.post(`/pdks/${tip === 'GIRIS' ? 'check-in' : 'check-out'}`,
        { method: 'GPS', ...konum, device_integrity: WEB_INTEGRITY },
        { noToast: true, busyMessage: 'Konum doğrulanıyor...' });
      toast(tip === 'GIRIS' ? 'Giriş kaydedildi' : 'Çıkış kaydedildi');
      setReload((n) => n + 1);
    } catch (e) {
      toast(errorMessage(e) || e.message);
    } finally {
      setMesgul(false);
    }
  }

  async function qrIslem(tip, token) {
    setOkuyucu(null);
    setMesgul(true);
    try {
      // Sabit basili kod konum da istiyor; konum alinabiliyorsa gonderilir.
      let konum = {};
      try { konum = await konumAl(); } catch { /* QR tek basina yeterli olabilir */ }
      await api.post(`/pdks/${tip === 'GIRIS' ? 'check-in' : 'check-out'}`,
        { method: 'QR', qr_token: token, ...konum, device_integrity: WEB_INTEGRITY },
        { noToast: true, busyMessage: 'QR doğrulanıyor...' });
      toast(tip === 'GIRIS' ? 'Giriş kaydedildi' : 'Çıkış kaydedildi');
      setReload((n) => n + 1);
    } catch (e) {
      toast(errorMessage(e));
    } finally {
      setMesgul(false);
    }
  }

  async function kendiQrKodu() {
    try {
      const r = await api.get('/pdks/me/qr', { silent: true });
      setQrGoster(r.data);
    } catch (e) {
      toast(errorMessage(e));
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
  const magaza = durum.store || {};
  const konumVar = magaza.has_location;
  const pdksAcik = magaza.pdks_enabled;

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Clock size={20} /> Devam Takibi</h2>
        <span className={`badge ${iceride ? 'sold' : 'discarded'}`}>
          {iceride ? 'İş yerindesiniz' : 'İş yerinde değilsiniz'}
        </span>
      </div>

      {!pdksAcik && (
        <div className="alert warning">
          Bu mağazada devam takibi henüz açılmamış. Yöneticinizle görüşün.
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
          </div>
        </div>

        <div className="pdks-actions">
          <button
            className={`btn ${iceride ? 'btn-secondary' : 'btn-primary'} btn-lg`}
            disabled={mesgul || !pdksAcik || iceride || !konumVar}
            onClick={() => gpsIslem('GIRIS')}
          >
            <LogIn size={18} /> Konumla İşe Başla
          </button>
          <button
            className={`btn ${iceride ? 'btn-primary' : 'btn-secondary'} btn-lg`}
            disabled={mesgul || !pdksAcik || !iceride || !konumVar}
            onClick={() => gpsIslem('CIKIS')}
          >
            <LogOut size={18} /> Konumla İşi Bitir
          </button>
        </div>

        <div className="pdks-actions">
          <button className="btn btn-secondary" disabled={mesgul || !pdksAcik}
            onClick={() => setOkuyucu(iceride ? 'CIKIS' : 'GIRIS')}>
            <ScanLine size={16} /> QR Okut ({iceride ? 'çıkış' : 'giriş'})
          </button>
          <button className="btn btn-secondary" disabled={!pdksAcik} onClick={kendiQrKodu}>
            <QrIcon size={16} /> Kodumu Göster
          </button>
        </div>

        {!konumVar && pdksAcik && (
          <p className="muted" style={{ fontSize: 12, margin: '8px 0 0' }}>
            Mağaza konumu tanımlanmadığı için konumla giriş kapalı. QR ile giriş yapabilirsiniz.
          </p>
        )}
        <p className="muted" style={{ fontSize: 12, margin: '8px 0 0', display: 'flex', gap: 6 }}>
          <MapPin size={14} />
          Konumunuz yalnızca giriş/çıkış anında alınır ve
          {konumVar ? ` ${magaza.geofence_radius_m} m ` : ' '}
          iş yeri yarıçapıyla karşılaştırılır. Arka planda konum izlenmez.
        </p>
      </section>

      {/* --- Bugunun vardiyasi ve kayitlari --- */}
      <section className="surface-panel">
        <h3 style={{ margin: '0 0 8px', fontSize: 15 }}>Bugün</h3>
        {durum.shifts.length === 0 ? (
          <p className="muted" style={{ fontSize: 13, margin: 0 }}>Bugün için vardiya atanmamış.</p>
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
          <p className="muted" style={{ fontSize: 13, margin: 0 }}>Bugün kayıt yok.</p>
        ) : (
          <ul className="pdks-log-list">
            {durum.logs.map((l) => (
              <li key={l.id}>
                <span className={`badge ${l.type === 'GIRIS' ? 'sold' : 'discarded'}`}>
                  {l.type === 'GIRIS' ? 'Giriş' : 'Çıkış'}
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
      </section>

      {/* --- Bakiye --- */}
      {bakiye && (
        <section className="surface-panel">
          <div className="mo-head">
            <h3><Wallet size={18} /> İzin ve Avans Durumu</h3>
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
            <div className="mo-figure">
              <span>Kalan avans</span>
              <strong className="text-ok">{fmtMoney(bakiye.advance.remaining)}</strong>
            </div>
          </div>
          {bakiye.hourly_leave.used_hours > 0 && (
            <p className="muted" style={{ fontSize: 12, margin: '8px 0 0' }}>
              Bu ay {bakiye.hourly_leave.used_hours} saat saatlik izin kullanıldı
              (yıllık izin gününden düşülmez).
            </p>
          )}
          {bakiye.notes.map((n, i) => (
            <p className="muted" key={i} style={{ fontSize: 11, margin: '4px 0 0' }}>{n}</p>
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
        {talepler.length === 0 ? (
          <p className="empty">Henüz talebiniz yok.</p>
        ) : (
          <div className="table-wrap">
            <table className="responsive">
              <thead>
                <tr><th>Tür</th><th>Detay</th><th>Durum</th><th>Karar</th><th>İşlem</th></tr>
              </thead>
              <tbody>
                {talepler.map((r) => (
                  <tr key={r.id}>
                    <td data-label="Tür"><strong>{TALEP_ETIKET[r.type]}</strong></td>
                    <td data-label="Detay">
                      {r.type === 'AVANS' ? fmtMoney(r.amount)
                        : r.type === 'IZIN' ? `${fmtDate(r.start_at)} – ${fmtDate(r.end_at)} (${r.days} gün)`
                        : `${fmtDateTime(r.start_at)} · ${r.hours} saat`}
                      <div className="muted" style={{ fontSize: 12 }}>{r.reason}</div>
                    </td>
                    <td data-label="Durum">
                      <span className={`badge ${DURUM_SINIF[r.status]}`}>{DURUM_ETIKET[r.status]}</span>
                    </td>
                    <td data-label="Karar" className="muted" style={{ fontSize: 12 }}>
                      {r.manager_name || '-'}
                      {r.decision_note && <div>{r.decision_note}</div>}
                    </td>
                    <td data-label="İşlem">
                      {r.status === 'PENDING' && (
                        <button className="btn btn-sm btn-secondary" onClick={async () => {
                          try {
                            await api.post(`/pdks/requests/${r.id}/cancel`, undefined,
                              { successMessage: 'Talep geri alındı' });
                            setReload((n) => n + 1);
                          } catch { /* bildirim api katmaninda */ }
                        }}>Geri Al</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* --- Aylik vardiya takvimi --- */}
      <section className="surface-panel">
        <div className="mo-head">
          <h3><CalendarDays size={18} /> Vardiya Takvimi</h3>
          <input type="month" value={ay} onChange={(e) => setAy(e.target.value)} />
        </div>
        <Takvim ay={ay} atamalar={takvim} tatiller={tatiller} />
      </section>

      {qrGoster && (
        <Modal title="Kodumu Göster" onClose={() => setQrGoster(null)}>
          <QrCode value={qrGoster.token}
            label={`Kiosk bu kodu okutacak · ${qrGoster.expires_in} saniye geçerli`} />
          <p className="muted" style={{ fontSize: 12 }}>
            Kod {qrGoster.window_seconds} saniyede bir yenilenir. Süre dolarsa
            pencereyi kapatıp tekrar açın.
          </p>
          <div className="form-actions">
            <button className="btn btn-secondary" onClick={kendiQrKodu}>
              <RefreshCw size={16} /> Yenile
            </button>
            <button className="btn btn-primary" onClick={() => setQrGoster(null)}>Kapat</button>
          </div>
        </Modal>
      )}

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
        <p className="muted" style={{ fontSize: 13, margin: '10px 0 0' }}>
          Bu ay için vardiya atanmamış.
        </p>
      )}
      {tatiller.length > 0 && (
        <p className="muted" style={{ fontSize: 11, margin: '8px 0 0' }}>
          Kırmızı çerçeveli günler resmi tatil; yıllık izin hakkınızdan düşülmez.
        </p>
      )}
    </>
  );
}

/// Izin / saatlik izin / avans talep formu.
function TalepModal({ bakiye, onClose, onDone }) {
  const [tur, setTur] = useState('IZIN');
  const [baslangic, setBaslangic] = useState('');
  const [bitis, setBitis] = useState('');
  const [saatBas, setSaatBas] = useState('');
  const [saatBit, setSaatBit] = useState('');
  const [tutar, setTutar] = useState('');
  const [gerekce, setGerekce] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  async function gonder(e) {
    e.preventDefault();
    setErr('');
    const govde = { type: tur, reason: gerekce.trim() };
    if (!govde.reason) { setErr('Gerekçe zorunludur'); return; }
    if (tur === 'IZIN') {
      if (!baslangic || !bitis) { setErr('Tarih aralığı seçin'); return; }
      govde.start_at = baslangic;
      govde.end_at = bitis;
    } else if (tur === 'SAATLIK_IZIN') {
      if (!saatBas || !saatBit) { setErr('Saat aralığı seçin'); return; }
      // datetime-local yerel saat verir; ISO'ya cevrilir.
      govde.start_at = new Date(saatBas).toISOString();
      govde.end_at = new Date(saatBit).toISOString();
    } else {
      const n = Number(tutar);
      if (!Number.isFinite(n) || n <= 0) { setErr('Tutar 0’dan büyük olmalıdır'); return; }
      govde.amount = n;
    }
    setBusy(true);
    try {
      await api.post('/pdks/requests', govde, { noToast: true, busyMessage: 'Talep gönderiliyor...' });
      toast('Talep gönderildi, onay bekliyor');
      onDone();
    } catch (e2) {
      setErr(errorMessage(e2));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Yeni Talep" onClose={onClose}>
      <form onSubmit={gonder}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Talep Türü</label>
          <select value={tur} onChange={(e) => setTur(e.target.value)}>
            <option value="IZIN">Yıllık İzin</option>
            <option value="SAATLIK_IZIN">Saatlik İzin</option>
            <option value="AVANS">Avans</option>
          </select>
        </div>

        {tur === 'IZIN' && (
          <>
            <div className="field">
              <label>Başlangıç</label>
              <input type="date" value={baslangic} onChange={(e) => setBaslangic(e.target.value)} required />
            </div>
            <div className="field">
              <label>Bitiş</label>
              <input type="date" value={bitis} onChange={(e) => setBitis(e.target.value)} required />
            </div>
            {bakiye && (
              <p className="muted" style={{ fontSize: 12 }}>
                Kalan hakkınız {bakiye.leave.remaining_days} gün. Hafta tatili günleri
                düşülmez, resmi tatiller hesaba katılmaz.
              </p>
            )}
          </>
        )}

        {tur === 'SAATLIK_IZIN' && (
          <>
            <div className="field">
              <label>Başlangıç</label>
              <input type="datetime-local" value={saatBas} onChange={(e) => setSaatBas(e.target.value)} required />
            </div>
            <div className="field">
              <label>Bitiş</label>
              <input type="datetime-local" value={saatBit} onChange={(e) => setSaatBit(e.target.value)} required />
            </div>
            <p className="muted" style={{ fontSize: 12 }}>
              Aynı gün içinde ve en fazla 12 saat olabilir.
            </p>
          </>
        )}

        {tur === 'AVANS' && (
          <div className="field">
            <label>Tutar (₺)</label>
            <input value={tutar} onChange={(e) => setTutar(e.target.value)} inputMode="decimal" required />
            {bakiye && (
              <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
                Bu ay kalan avans limitiniz {fmtMoney(bakiye.advance.remaining)}.
              </p>
            )}
          </div>
        )}

        <div className="field">
          <label>Gerekçe</label>
          <input value={gerekce} onChange={(e) => setGerekce(e.target.value)} required />
        </div>

        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Gönderiliyor...' : 'Gönder'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
