import { useCallback, useEffect, useState } from 'react';
import {
  Users, ClipboardCheck, Table2, CalendarClock, Settings, QrCode as QrIcon,
  MapPin, Plus, Trash2, RefreshCw, CalendarDays, ShieldCheck,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, toast } from '../components/ui';
import QrCode from '../components/pdks/QrCode';
import { fmtDate, fmtDateTime, fmtMoney, errorMessage } from '../format';

// Yonetici PDKS ekrani: anlik durum, talep onayi, puantaj, vardiya, ayarlar.

const SEKMELER = [
  { id: 'now', label: 'Anlık Durum', ico: Users },
  { id: 'requests', label: 'Talepler', ico: ClipboardCheck },
  { id: 'timesheet', label: 'Puantaj', ico: Table2 },
  { id: 'shifts', label: 'Vardiyalar', ico: CalendarClock },
  { id: 'holidays', label: 'Tatiller', ico: CalendarDays },
  { id: 'settings', label: 'Ayarlar', ico: Settings },
];

const saat = (dk) => {
  if (!dk) return '-';
  return `${Math.floor(dk / 60)}s ${dk % 60}dk`;
};
const TALEP_ETIKET = { IZIN: 'Yıllık İzin', SAATLIK_IZIN: 'Saatlik İzin', AVANS: 'Avans' };

function ayBasi() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
}
function bugun() {
  return new Date().toISOString().slice(0, 10);
}

export default function PdksAdmin() {
  const { user } = useAuth();
  const [sekme, setSekme] = useState('now');
  const [bekleyen, setBekleyen] = useState(0);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    api.get('/pdks/requests?status=PENDING', { silent: true })
      .then((r) => setBekleyen(r.data.length)).catch(() => {});
  }, [reload]);

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Users size={20} /> Devam Takibi Yönetimi</h2>
        {bekleyen > 0 && <span className="badge warning">{bekleyen} bekleyen talep</span>}
      </div>

      <div className="chip-row" style={{ marginBottom: 12 }}>
        {SEKMELER.map((s) => (
          <button key={s.id} type="button"
            className={`chip ${sekme === s.id ? 'chip-on' : ''}`}
            onClick={() => setSekme(s.id)}>
            <s.ico size={14} /> {s.label}
            {s.id === 'requests' && bekleyen > 0 ? ` (${bekleyen})` : ''}
          </button>
        ))}
      </div>

      {sekme === 'now' && <AnlikDurum />}
      {sekme === 'requests' && <Talepler onChange={() => setReload((n) => n + 1)} />}
      {sekme === 'timesheet' && <Puantaj />}
      {sekme === 'shifts' && <Vardiyalar isSuper={user.role === 'super_admin'} />}
      {sekme === 'holidays' && <Tatiller isSuper={user.role === 'super_admin'} />}
      {sekme === 'settings' && <Ayarlar isSuper={user.role === 'super_admin'} />}
    </div>
  );
}

// ---- Anlik durum ----

function AnlikDurum() {
  const [veri, setVeri] = useState(null);
  const [hata, setHata] = useState('');

  const yukle = useCallback(() => {
    api.get('/pdks/now', { silent: true })
      .then((r) => { setVeri(r.data); setHata(''); })
      .catch((e) => setHata(errorMessage(e)));
  }, []);

  useEffect(() => {
    yukle();
    // 60 saniyelik yenileme: "su an kimler iste" canli olmali.
    const t = setInterval(yukle, 60000);
    return () => clearInterval(t);
  }, [yukle]);

  if (hata) return <div className="alert error">{hata}</div>;
  if (!veri) return null;

  const satir = (k, iceride) => (
    <tr key={k.user_id}>
      <td data-label="Personel">
        <span className={`mo-dot ${iceride ? 'ok' : 'danger'}`} />
        <strong>{k.full_name}</strong>
      </td>
      <td data-label="Son işlem">
        {k.last_type
          ? <span className={`badge ${k.last_type === 'GIRIS' ? 'sold' : 'discarded'}`}>
              {k.last_type === 'GIRIS' ? 'Giriş' : 'Çıkış'}
            </span>
          : <span className="muted">kayıt yok</span>}
      </td>
      <td data-label="Zaman" className="muted" style={{ fontSize: 13 }}>
        {k.last_at ? fmtDateTime(k.last_at) : '-'}
      </td>
      <td data-label="Süre">
        {iceride && k.minutes_since !== null ? saat(k.minutes_since) : '-'}
      </td>
      <td data-label="Yöntem">{k.last_method || '-'}</td>
      <td data-label="Mesafe">
        {k.distance_m !== null && k.distance_m !== undefined
          ? `${Math.round(k.distance_m)} m` : '-'}
      </td>
    </tr>
  );

  return (
    <>
      <div className="surface-panel">
        <div className="mo-head">
          <h3>Şu an işte: {veri.inside_count} kişi</h3>
          <span className="muted">{fmtDateTime(veri.as_of)} · 60 saniyede yenilenir</span>
        </div>
        <button className="btn btn-sm btn-secondary" onClick={yukle}>
          <RefreshCw size={14} /> Yenile
        </button>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Personel</th><th>Son işlem</th><th>Zaman</th><th>Süre</th>
                <th>Yöntem</th><th>Mesafe</th></tr>
            </thead>
            <tbody>
              {veri.inside.length === 0 && veri.outside.length === 0 && (
                <tr><td data-label="" colSpan="6"><p className="empty">Personel bulunamadı.</p></td></tr>
              )}
              {veri.inside.map((k) => satir(k, true))}
              {veri.outside.map((k) => satir(k, false))}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}

// ---- Talepler ----

function Talepler({ onChange }) {
  const [liste, setListe] = useState([]);
  const [durum, setDurum] = useState('PENDING');
  const [ret, setRet] = useState(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    api.get(`/pdks/requests${durum ? `?status=${durum}` : ''}`, { silent: true })
      .then((r) => setListe(r.data)).catch(() => {});
  }, [durum, reload]);

  async function karar(r, onayla, note) {
    try {
      await api.post(`/pdks/requests/${r.id}/${onayla ? 'approve' : 'reject'}`,
        note ? { note } : undefined,
        { successMessage: onayla ? 'Talep onaylandı' : 'Talep reddedildi' });
      setReload((n) => n + 1);
      onChange();
    } catch { /* bildirim api katmaninda */ }
  }

  return (
    <>
      <div className="surface-panel">
        <div className="chip-row">
          {[['PENDING', 'Bekleyen'], ['APPROVED', 'Onaylanan'], ['REJECTED', 'Reddedilen'], ['', 'Tümü']]
            .map(([v, l]) => (
              <button key={v} type="button" className={`chip ${durum === v ? 'chip-on' : ''}`}
                onClick={() => setDurum(v)}>{l}</button>
            ))}
        </div>
        <p className="muted" style={{ fontSize: 13, margin: '10px 0 0' }}>
          Onaylanan izin günlerine vardiya atanmaz ve o günler puantajda izin
          olarak sayılır. Reddedilen talebin tutarı/günü personelin hakkına geri döner.
        </p>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Personel</th><th>Tür</th><th>Detay</th><th>Gerekçe</th>
                <th>Durum</th><th>İşlem</th></tr>
            </thead>
            <tbody>
              {liste.length === 0 && (
                <tr><td data-label="" colSpan="6"><p className="empty">Kayıt bulunamadı.</p></td></tr>
              )}
              {liste.map((r) => (
                <tr key={r.id}>
                  <td data-label="Personel"><strong>{r.full_name}</strong></td>
                  <td data-label="Tür">{TALEP_ETIKET[r.type]}</td>
                  <td data-label="Detay">
                    {r.type === 'AVANS' ? fmtMoney(r.amount)
                      : r.type === 'IZIN' ? `${fmtDate(r.start_at)} – ${fmtDate(r.end_at)} (${r.days} gün)`
                      : `${fmtDateTime(r.start_at)} · ${r.hours} saat`}
                  </td>
                  <td data-label="Gerekçe" style={{ maxWidth: 200 }}>{r.reason}</td>
                  <td data-label="Durum">
                    <span className={`badge ${r.status === 'PENDING' ? 'warning'
                      : r.status === 'APPROVED' ? 'sold' : 'critical'}`}>
                      {r.status === 'PENDING' ? 'Bekliyor'
                        : r.status === 'APPROVED' ? 'Onaylandı'
                        : r.status === 'REJECTED' ? 'Reddedildi' : 'İptal'}
                    </span>
                    {r.decision_note && (
                      <div className="muted" style={{ fontSize: 11 }}>{r.decision_note}</div>
                    )}
                  </td>
                  <td data-label="İşlem">
                    {r.status === 'PENDING' && (
                      <div className="row-actions">
                        <button className="btn btn-sm btn-primary" onClick={() => karar(r, true)}>Onayla</button>
                        <button className="btn btn-sm btn-danger" onClick={() => setRet(r)}>Reddet</button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {ret && (
        <RetModal talep={ret} onClose={() => setRet(null)}
          onDone={(note) => { const t = ret; setRet(null); karar(t, false, note); }} />
      )}
    </>
  );
}

function RetModal({ talep, onClose, onDone }) {
  const [note, setNote] = useState('');
  const [err, setErr] = useState('');
  return (
    <Modal title="Talebi Reddet" onClose={onClose}>
      <form onSubmit={(e) => {
        e.preventDefault();
        if (!note.trim()) { setErr('Ret gerekçesi zorunludur'); return; }
        onDone(note.trim());
      }}>
        {err && <div className="alert error">{err}</div>}
        <p className="muted" style={{ fontSize: 13, margin: '0 0 12px' }}>
          {talep.full_name} · {TALEP_ETIKET[talep.type]}
        </p>
        <div className="field">
          <label>Ret Gerekçesi</label>
          <input value={note} onChange={(e) => setNote(e.target.value)} autoFocus required />
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            Personel bu gerekçeyi görecek.
          </p>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-danger">Reddet</button>
        </div>
      </form>
    </Modal>
  );
}

// ---- Puantaj ----

function Puantaj() {
  const [from, setFrom] = useState(ayBasi);
  const [to, setTo] = useState(bugun);
  const [veri, setVeri] = useState(null);
  const [hata, setHata] = useState('');
  const [acik, setAcik] = useState(null);

  useEffect(() => {
    setHata('');
    api.get(`/pdks/timesheet?from=${from}&to=${to}`)
      .then((r) => setVeri(r.data))
      .catch((e) => { setVeri(null); setHata(errorMessage(e)); });
  }, [from, to]);

  return (
    <>
      <div className="surface-panel">
        <div className="filters">
          <label>Başlangıç <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
          <label>Bitiş <input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label>
        </div>
        {veri && veri.notes.map((n, i) => (
          <p className="muted" key={i} style={{ fontSize: 12, margin: '4px 0 0' }}>{n}</p>
        ))}
      </div>

      {hata && <div className="alert error">{hata}</div>}

      {veri && (
        <>
          <div className="card table-card">
            <div className="table-wrap">
              <table className="responsive">
                <thead>
                  <tr><th>Personel</th><th>Çalışılan</th><th>Planlı</th><th>Fazla mesai</th>
                    <th>Eksik</th><th>Geç</th><th>İzin</th><th>Devamsız</th><th></th></tr>
                </thead>
                <tbody>
                  {veri.items.length === 0 && (
                    <tr><td data-label="" colSpan="9"><p className="empty">Kayıt bulunamadı.</p></td></tr>
                  )}
                  {veri.items.map((it) => (
                    <tr key={it.user.id}>
                      <td data-label="Personel"><strong>{it.user.full_name}</strong></td>
                      <td data-label="Çalışılan">{saat(it.summary.worked_minutes)}</td>
                      <td data-label="Planlı">{saat(it.summary.scheduled_minutes)}</td>
                      <td data-label="Fazla mesai">
                        <strong className="text-ok">{saat(it.summary.overtime_minutes)}</strong>
                      </td>
                      <td data-label="Eksik">
                        <strong className={it.summary.missing_minutes ? 'text-danger' : ''}>
                          {saat(it.summary.missing_minutes)}
                        </strong>
                      </td>
                      <td data-label="Geç">{it.summary.late_minutes || 0} dk</td>
                      <td data-label="İzin">{it.summary.leave_days} gün</td>
                      <td data-label="Devamsız">
                        {it.summary.absent_days > 0
                          ? <span className="badge critical">{it.summary.absent_days} gün</span>
                          : '-'}
                      </td>
                      <td data-label="">
                        <button className="btn btn-sm btn-secondary"
                          onClick={() => setAcik(acik === it.user.id ? null : it.user.id)}>
                          {acik === it.user.id ? 'Kapat' : 'Gün gün'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {veri.total.unscheduled_minutes > 0 && (
            <div className="alert warning">
              {saat(veri.total.unscheduled_minutes)} çalışma, vardiya atanmamış
              {' '}{veri.total.unscheduled_days} günde yapılmış. Bu süre fazla mesai ya da
              eksik olarak sınıflandırılmadı — ilgili günlere vardiya atayın.
            </div>
          )}

          {acik && (
            <GunGun item={veri.items.find((i) => i.user.id === acik)} />
          )}
        </>
      )}
    </>
  );
}

function GunGun({ item }) {
  if (!item) return null;
  return (
    <div className="card table-card">
      <div className="surface-panel" style={{ border: 0, marginBottom: 0 }}>
        <h3 style={{ margin: 0, fontSize: 15 }}>{item.user.full_name} — gün gün</h3>
      </div>
      <div className="table-wrap">
        <table className="responsive">
          <thead>
            <tr><th>Gün</th><th>Vardiya</th><th>Durum</th><th>Bulunma</th><th>Net</th>
              <th>Planlı</th><th>Mesai</th><th>Eksik</th></tr>
          </thead>
          <tbody>
            {item.days.map((d) => (
              <tr key={d.work_date}>
                <td data-label="Gün"><strong>{fmtDate(d.work_date)}</strong></td>
                <td data-label="Vardiya" className="muted" style={{ fontSize: 12 }}>
                  {d.is_day_off ? 'Hafta tatili' : (d.shift_names.join(', ') || '-')}
                </td>
                <td data-label="Durum">
                  {d.statuses.length === 0 ? '-' : d.statuses.map((s) => (
                    <span className={`badge ${s === 'DEVAMSIZ' || s === 'ESLESMEYEN_KAYIT' ? 'critical'
                      : s === 'IZINLI' ? 'sold' : 'warning'}`} key={s}
                      style={{ marginRight: 4 }}>{s.replaceAll('_', ' ').toLowerCase()}</span>
                  ))}
                </td>
                <td data-label="Bulunma">{saat(d.presence_minutes)}</td>
                <td data-label="Net">{saat(d.worked_minutes)}</td>
                <td data-label="Planlı">{saat(d.scheduled_minutes)}</td>
                <td data-label="Mesai">{saat(d.overtime_minutes)}</td>
                <td data-label="Eksik">{saat(d.missing_minutes)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---- Vardiyalar ----

function Vardiyalar({ isSuper }) {
  const [liste, setListe] = useState([]);
  const [form, setForm] = useState(null);
  const [atama, setAtama] = useState(false);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    api.get('/pdks/shifts?all=1', { silent: true }).then((r) => setListe(r.data)).catch(() => {});
  }, [reload]);

  async function sil(s) {
    if (!window.confirm(`${s.name} vardiyası silinecek.`)) return;
    try {
      await api.delete(`/pdks/shifts/${s.id}`, { successMessage: 'Vardiya silindi' });
      setReload((n) => n + 1);
    } catch { /* bildirim api katmaninda */ }
  }

  return (
    <>
      <div className="surface-panel">
        <div className="mo-head">
          <h3>Vardiya Tanımları</h3>
          <div className="row-actions">
            <button className="btn btn-sm btn-secondary" onClick={() => setAtama(true)}>
              <CalendarClock size={14} /> Toplu Ata
            </button>
            <button className="btn btn-sm btn-primary" onClick={() => setForm({})}>
              <Plus size={14} /> Yeni Vardiya
            </button>
          </div>
        </div>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Ad</th><th>Saat</th><th>Mola</th><th>Geç toleransı</th>
                <th>Mesai eşiği</th><th>Mağaza</th><th>Durum</th><th>İşlem</th></tr>
            </thead>
            <tbody>
              {liste.length === 0 && (
                <tr><td data-label="" colSpan="8"><p className="empty">Vardiya tanımlanmamış.</p></td></tr>
              )}
              {liste.map((s) => (
                <tr key={s.id}>
                  <td data-label="Ad"><strong>{s.name}</strong></td>
                  <td data-label="Saat">
                    {s.start_time}–{s.end_time}
                    {s.end_time <= s.start_time && (
                      <div className="muted" style={{ fontSize: 11 }}>gece vardiyası</div>
                    )}
                  </td>
                  <td data-label="Mola">{s.break_duration_minutes} dk</td>
                  <td data-label="Geç toleransı">{s.late_tolerance_minutes} dk</td>
                  <td data-label="Mesai eşiği">{s.overtime_starts_after_minutes} dk</td>
                  <td data-label="Mağaza">{s.store_name || 'Tüm mağazalar'}</td>
                  <td data-label="Durum">
                    <span className={`badge ${s.active ? 'sold' : 'discarded'}`}>
                      {s.active ? 'Aktif' : 'Pasif'}
                    </span>
                  </td>
                  <td data-label="İşlem">
                    <div className="row-actions">
                      <button className="btn btn-sm btn-secondary" onClick={() => setForm(s)}>Düzenle</button>
                      <button className="btn btn-sm btn-danger" onClick={() => sil(s)}>
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {form && (
        <VardiyaModal vardiya={form.id ? form : null} isSuper={isSuper}
          onClose={() => setForm(null)}
          onDone={() => { setForm(null); setReload((n) => n + 1); }} />
      )}
      {atama && (
        <AtamaModal vardiyalar={liste.filter((s) => s.active)}
          onClose={() => setAtama(false)} onDone={() => setAtama(false)} />
      )}
    </>
  );
}

function VardiyaModal({ vardiya, isSuper, onClose, onDone }) {
  const [v, setV] = useState(() => ({
    name: vardiya?.name || '',
    start_time: vardiya?.start_time || '08:00',
    end_time: vardiya?.end_time || '17:00',
    break_duration_minutes: vardiya?.break_duration_minutes ?? 60,
    late_tolerance_minutes: vardiya?.late_tolerance_minutes ?? 10,
    early_leave_tolerance_minutes: vardiya?.early_leave_tolerance_minutes ?? 5,
    overtime_starts_after_minutes: vardiya?.overtime_starts_after_minutes ?? 15,
    active: vardiya ? !!vardiya.active : true,
  }));
  const [tumMagazalar, setTumMagazalar] = useState(false);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const alan = (k, val) => setV((s) => ({ ...s, [k]: val }));

  async function gonder(e) {
    e.preventDefault();
    setErr('');
    setBusy(true);
    try {
      const govde = { ...v };
      if (!vardiya && tumMagazalar) govde.store_id = null;
      if (vardiya) await api.put(`/pdks/shifts/${vardiya.id}`, govde, { noToast: true });
      else await api.post('/pdks/shifts', govde, { noToast: true });
      toast(vardiya ? 'Vardiya güncellendi' : 'Vardiya oluşturuldu');
      onDone();
    } catch (e2) {
      setErr(errorMessage(e2));
    } finally {
      setBusy(false);
    }
  }

  const sayi = (k, l, ipucu) => (
    <div className="field" key={k}>
      <label>{l}</label>
      <input value={v[k]} inputMode="numeric"
        onChange={(e) => alan(k, e.target.value === '' ? '' : Number(e.target.value))} />
      {ipucu && <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>{ipucu}</p>}
    </div>
  );

  return (
    <Modal title={vardiya ? 'Vardiyayı Düzenle' : 'Yeni Vardiya'} onClose={onClose}>
      <form onSubmit={gonder}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Vardiya Adı</label>
          <input value={v.name} onChange={(e) => alan('name', e.target.value)} required />
        </div>
        <div className="field">
          <label>Başlangıç</label>
          <input type="time" value={v.start_time} onChange={(e) => alan('start_time', e.target.value)} required />
        </div>
        <div className="field">
          <label>Bitiş</label>
          <input type="time" value={v.end_time} onChange={(e) => alan('end_time', e.target.value)} required />
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            Bitiş başlangıçtan küçük veya eşitse vardiya gece yarısını geçer (örn. 22:00–06:00).
          </p>
        </div>
        {sayi('break_duration_minutes', 'Mola (dk)',
          'İş Kanunu m.68 asgarisi ile bu değerin küçüğü düşülür.')}
        {sayi('late_tolerance_minutes', 'Geç kalma toleransı (dk)')}
        {sayi('early_leave_tolerance_minutes', 'Erken çıkış toleransı (dk)')}
        {sayi('overtime_starts_after_minutes', 'Fazla mesai eşiği (dk)',
          'Bu süreden kısa sarkmalar mesaiye yazılmaz.')}
        {!vardiya && isSuper && (
          <div className="field">
            <label>
              <input type="checkbox" checked={tumMagazalar}
                onChange={(e) => setTumMagazalar(e.target.checked)} /> Tüm mağazalarda kullanılabilir
            </label>
          </div>
        )}
        {vardiya && (
          <div className="field">
            <label>
              <input type="checkbox" checked={v.active}
                onChange={(e) => alan('active', e.target.checked)} /> Aktif
            </label>
          </div>
        )}
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Kaydediliyor...' : 'Kaydet'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

function AtamaModal({ vardiyalar, onClose, onDone }) {
  const [personel, setPersonel] = useState([]);
  const [secili, setSecili] = useState([]);
  const [shiftId, setShiftId] = useState(vardiyalar[0]?.id || '');
  const [tatil, setTatil] = useState(false);
  const [from, setFrom] = useState(bugun);
  const [to, setTo] = useState(bugun);
  const [err, setErr] = useState('');
  const [sonuc, setSonuc] = useState(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.get('/pdks/profiles', { silent: true }).then((r) => setPersonel(r.data)).catch(() => {});
  }, []);

  async function gonder(e) {
    e.preventDefault();
    setErr('');
    if (secili.length === 0) { setErr('En az bir personel seçin'); return; }
    setBusy(true);
    try {
      const r = await api.post('/pdks/assignments', {
        user_ids: secili, shift_id: tatil ? null : Number(shiftId),
        is_day_off: tatil, from, to,
      }, { noToast: true, busyMessage: 'Atanıyor...' });
      setSonuc(r.data);
      toast(`${r.data.assigned} gün atandı`);
    } catch (e2) {
      setErr(errorMessage(e2));
    } finally {
      setBusy(false);
    }
  }

  if (sonuc) {
    return (
      <Modal title="Atama Sonucu" onClose={onDone}>
        <p><strong>{sonuc.assigned} gün</strong> atandı.</p>
        <ul className="pdks-log-list">
          {sonuc.users.map((u) => (
            <li key={u.user_id}>
              <strong>{u.full_name}</strong>
              <span className="muted">{u.days} gün</span>
              {u.skipped_dates.length > 0 && (
                <span className="badge warning">
                  {u.skipped_dates.length} gün izinli, atlandı
                </span>
              )}
            </li>
          ))}
        </ul>
        {sonuc.skipped.length > 0 && (
          <div className="alert warning">
            {sonuc.skipped.length} personel atlandı (yetki ya da mağaza uyumsuzluğu).
          </div>
        )}
        <p className="muted" style={{ fontSize: 12 }}>
          Hafta tatili günleri ve onaylı izin günleri atlanır.
        </p>
        <div className="form-actions">
          <button className="btn btn-primary" onClick={onDone}>Kapat</button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal title="Toplu Vardiya Ataması" onClose={onClose}>
      <form onSubmit={gonder}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>
            <input type="checkbox" checked={tatil} onChange={(e) => setTatil(e.target.checked)} />
            {' '}Hafta tatili olarak ata
          </label>
        </div>
        {!tatil && (
          <div className="field">
            <label>Vardiya</label>
            <select value={shiftId} onChange={(e) => setShiftId(e.target.value)} required>
              {vardiyalar.map((s) => (
                <option key={s.id} value={s.id}>{s.name} ({s.start_time}–{s.end_time})</option>
              ))}
            </select>
          </div>
        )}
        <div className="field">
          <label>Başlangıç</label>
          <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} required />
        </div>
        <div className="field">
          <label>Bitiş</label>
          <input type="date" value={to} onChange={(e) => setTo(e.target.value)} required />
        </div>
        <div className="field">
          <label>Personel ({secili.length} seçili)</label>
          <div className="pdks-picker">
            {personel.map((p) => (
              <label key={p.user_id} className="pdks-pick">
                <input type="checkbox" checked={secili.includes(p.user_id)}
                  onChange={(e) => setSecili((s) => e.target.checked
                    ? [...s, p.user_id] : s.filter((x) => x !== p.user_id))} />
                {p.full_name}
              </label>
            ))}
          </div>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Atanıyor...' : 'Ata'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

// ---- Ayarlar ----

function Ayarlar({ isSuper }) {
  const [liste, setListe] = useState([]);
  const [duzenle, setDuzenle] = useState(null);
  const [kiosk, setKiosk] = useState(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    api.get('/pdks/settings', { silent: true }).then((r) => setListe(r.data)).catch(() => {});
  }, [reload]);

  async function kioskKodu(s) {
    try {
      const r = await api.get(`/pdks/qr/current?storeId=${s.id}`, { silent: true });
      setKiosk({ store: s, ...r.data });
    } catch (e) {
      toast(errorMessage(e));
    }
  }

  return (
    <>
      <div className="surface-panel">
        <p className="muted" style={{ fontSize: 13, margin: 0 }}>
          Devam takibi açılmadan önce mağaza konumu tanımlanmalıdır — konum
          doğrulaması buna dayanıyor. QR sırrı ilk açılışta otomatik üretilir ve
          hiçbir yerde görüntülenmez.
        </p>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Mağaza</th><th>Devam takibi</th><th>Konum</th><th>Yarıçap</th>
                <th>QR kipi</th><th>İşlem</th></tr>
            </thead>
            <tbody>
              {liste.map((s) => (
                <tr key={s.id}>
                  <td data-label="Mağaza"><strong>{s.name}</strong></td>
                  <td data-label="Devam takibi">
                    <span className={`badge ${s.pdks_enabled ? 'sold' : 'discarded'}`}>
                      {s.pdks_enabled ? 'Açık' : 'Kapalı'}
                    </span>
                  </td>
                  <td data-label="Konum">
                    {s.latitude !== null && s.longitude !== null
                      ? <span className="muted" style={{ fontSize: 12 }}>
                          {Number(s.latitude).toFixed(5)}, {Number(s.longitude).toFixed(5)}
                        </span>
                      : <span className="badge critical">tanımsız</span>}
                  </td>
                  <td data-label="Yarıçap">{s.geofence_radius_m} m</td>
                  <td data-label="QR kipi">
                    {s.qr_mode === 'rotating' ? 'Dönen kod' : 'Sabit kod'}
                  </td>
                  <td data-label="İşlem">
                    <div className="row-actions">
                      <button className="btn btn-sm btn-secondary" onClick={() => setDuzenle(s)}>
                        <MapPin size={14} /> Düzenle
                      </button>
                      {s.pdks_enabled && s.has_secret && (
                        <button className="btn btn-sm btn-secondary" onClick={() => kioskKodu(s)}>
                          <QrIcon size={14} /> Kiosk Kodu
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {isSuper && <KvkkPanel />}

      {duzenle && (
        <AyarModal magaza={duzenle} onClose={() => setDuzenle(null)}
          onDone={() => { setDuzenle(null); setReload((n) => n + 1); }} />
      )}
      {kiosk && <KioskModal veri={kiosk} onClose={() => setKiosk(null)} onYenile={() => kioskKodu(kiosk.store)} />}
    </>
  );
}

function AyarModal({ magaza, onClose, onDone }) {
  const [lat, setLat] = useState(magaza.latitude ?? '');
  const [lon, setLon] = useState(magaza.longitude ?? '');
  const [yaricap, setYaricap] = useState(magaza.geofence_radius_m);
  const [kip, setKip] = useState(magaza.qr_mode);
  const [acik, setAcik] = useState(!!magaza.pdks_enabled);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  function konumumuKullan() {
    if (!navigator.geolocation) { setErr('Bu cihaz konum desteklemiyor'); return; }
    navigator.geolocation.getCurrentPosition(
      (p) => { setLat(p.coords.latitude); setLon(p.coords.longitude); setErr(''); },
      () => setErr('Konum alınamadı'),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    );
  }

  async function gonder(e) {
    e.preventDefault();
    setErr('');
    setBusy(true);
    try {
      await api.put(`/pdks/settings/${magaza.id}`, {
        latitude: lat === '' ? null : Number(lat),
        longitude: lon === '' ? null : Number(lon),
        geofence_radius_m: Number(yaricap),
        qr_mode: kip,
        pdks_enabled: acik,
      }, { noToast: true });
      toast('Ayarlar kaydedildi');
      onDone();
    } catch (e2) {
      setErr(errorMessage(e2));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title={`${magaza.name} — Devam Takibi`} onClose={onClose}>
      <form onSubmit={gonder}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Enlem</label>
          <input value={lat} onChange={(e) => setLat(e.target.value)} inputMode="decimal" />
        </div>
        <div className="field">
          <label>Boylam</label>
          <input value={lon} onChange={(e) => setLon(e.target.value)} inputMode="decimal" />
          <button type="button" className="btn btn-sm btn-secondary" style={{ marginTop: 6 }}
            onClick={konumumuKullan}>
            <MapPin size={14} /> Bulunduğum konumu kullan
          </button>
        </div>
        <div className="field">
          <label>Geofence yarıçapı (m)</label>
          <input value={yaricap} onChange={(e) => setYaricap(e.target.value)} inputMode="numeric" />
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            20–5000 m. Şehir içi GPS sapması 20–50 m olabildiği için 100 m önerilir.
          </p>
        </div>
        <div className="field">
          <label>QR kipi</label>
          <select value={kip} onChange={(e) => setKip(e.target.value)}>
            <option value="rotating">Dönen kod (kiosk ekranı) — önerilen</option>
            <option value="static">Sabit basılı kod</option>
          </select>
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            Sabit kod fotoğraflanabildiği için tek başına yeterli sayılmaz;
            konum doğrulamasıyla birlikte geçerli olur.
          </p>
        </div>
        <div className="field">
          <label>
            <input type="checkbox" checked={acik} onChange={(e) => setAcik(e.target.checked)} />
            {' '}Devam takibi açık
          </label>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Kaydediliyor...' : 'Kaydet'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

function KioskModal({ veri, onClose, onYenile }) {
  return (
    <Modal title={`${veri.store.name} — Kiosk Kodu`} onClose={onClose}>
      <QrCode value={veri.token} size={260}
        label={veri.mode === 'rotating'
          ? `${veri.expires_in} saniye geçerli, ${veri.window_seconds} saniyede yenilenir`
          : 'Sabit kod — yazdırıp iş yerine asabilirsiniz'} />
      {/* Kamerasi calismayan cihazda elle girilebilsin. */}
      <div className="field">
        <label>Kod metni</label>
        <input value={veri.token} readOnly onFocus={(e) => e.target.select()} />
      </div>
      {veri.mode === 'static' && (
        <div className="alert warning">
          Sabit kod yalnızca iş yeri yarıçapı içindeyken geçerlidir.
        </div>
      )}
      <div className="form-actions">
        {veri.mode === 'rotating' && (
          <button className="btn btn-secondary" onClick={onYenile}>
            <RefreshCw size={16} /> Yenile
          </button>
        )}
        <button className="btn btn-primary" onClick={onClose}>Kapat</button>
      </div>
    </Modal>
  );
}

// ---- Resmi tatiller ----

function Tatiller({ isSuper }) {
  const [liste, setListe] = useState([]);
  const [yil, setYil] = useState(() => new Date().getFullYear());
  const [ekle, setEkle] = useState(false);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    api.get(`/pdks/holidays?from=${yil}-01-01&to=${yil}-12-31`, { silent: true })
      .then((r) => setListe(r.data)).catch(() => {});
  }, [yil, reload]);

  async function tohumla() {
    try {
      const r = await api.post(`/pdks/holidays/seed?year=${yil}`, undefined, { noToast: true });
      toast(r.data.added > 0
        ? `${r.data.added} sabit millî bayram eklendi`
        : 'Bu yılın sabit bayramları zaten ekli');
      setReload((n) => n + 1);
    } catch (e) {
      toast(errorMessage(e));
    }
  }

  async function sil(h) {
    if (!window.confirm(`${fmtDate(h.holiday_date)} — ${h.name} silinecek.`)) return;
    try {
      await api.delete(`/pdks/holidays/${h.id}`, { successMessage: 'Tatil silindi' });
      setReload((n) => n + 1);
    } catch { /* bildirim api katmaninda */ }
  }

  return (
    <>
      <div className="surface-panel">
        <div className="mo-head">
          <h3><CalendarDays size={18} /> Resmi Tatiller — {yil}</h3>
          <div className="row-actions">
            <button className="btn btn-sm btn-secondary" onClick={() => setYil((y) => y - 1)}>‹</button>
            <button className="btn btn-sm btn-secondary" onClick={() => setYil((y) => y + 1)}>›</button>
            {isSuper && (
              <button className="btn btn-sm btn-secondary" onClick={tohumla}>
                Millî bayramları ekle
              </button>
            )}
            <button className="btn btn-sm btn-primary" onClick={() => setEkle(true)}>
              <Plus size={14} /> Yeni Tatil
            </button>
          </div>
        </div>
        <p className="muted" style={{ fontSize: 13, margin: 0 }}>
          Resmi tatiller yıllık izin hakkından düşülmez ve puantajda planlı süre
          sıfır sayılır (o gün çalışma tamamen fazla mesai olur). Arife gibi yarım
          tatiller 0,5 gün sayılır.
        </p>
        <p className="muted" style={{ fontSize: 12, margin: '6px 0 0' }}>
          <strong>Dini bayramlar</strong> her yıl kaydığı için otomatik eklenmiyor;
          Ramazan ve Kurban Bayramı tarihlerini elle girmeniz gerekiyor.
        </p>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Tarih</th><th>Ad</th><th>Tür</th><th>Kapsam</th><th>İşlem</th></tr>
            </thead>
            <tbody>
              {liste.length === 0 && (
                <tr><td data-label="" colSpan="5">
                  <p className="empty">{yil} için tatil tanımlanmamış.</p>
                </td></tr>
              )}
              {liste.map((h) => (
                <tr key={h.id}>
                  <td data-label="Tarih"><strong>{fmtDate(h.holiday_date)}</strong></td>
                  <td data-label="Ad">{h.name}</td>
                  <td data-label="Tür">
                    <span className={`badge ${h.is_half_day ? 'warning' : 'critical'}`}>
                      {h.is_half_day ? 'Yarım gün' : 'Tam gün'}
                    </span>
                  </td>
                  <td data-label="Kapsam">{h.store_name || 'Tüm mağazalar'}</td>
                  <td data-label="İşlem">
                    <button className="btn btn-sm btn-danger" onClick={() => sil(h)}>
                      <Trash2 size={14} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {ekle && (
        <TatilModal isSuper={isSuper} onClose={() => setEkle(false)}
          onDone={() => { setEkle(false); setReload((n) => n + 1); }} />
      )}
    </>
  );
}

function TatilModal({ isSuper, onClose, onDone }) {
  const [tarih, setTarih] = useState('');
  const [ad, setAd] = useState('');
  const [yarim, setYarim] = useState(false);
  const [tumMagazalar, setTumMagazalar] = useState(false);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  async function gonder(e) {
    e.preventDefault();
    setErr('');
    setBusy(true);
    try {
      const govde = { holiday_date: tarih, name: ad.trim(), is_half_day: yarim };
      if (tumMagazalar) govde.store_id = null;
      await api.post('/pdks/holidays', govde, { noToast: true });
      toast('Tatil eklendi');
      onDone();
    } catch (e2) {
      setErr(errorMessage(e2));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Yeni Resmi Tatil" onClose={onClose}>
      <form onSubmit={gonder}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Tarih</label>
          <input type="date" value={tarih} onChange={(e) => setTarih(e.target.value)} required />
        </div>
        <div className="field">
          <label>Ad</label>
          <input value={ad} onChange={(e) => setAd(e.target.value)}
            placeholder="Ramazan Bayramı 1. Gün" required />
        </div>
        <div className="field">
          <label>
            <input type="checkbox" checked={yarim} onChange={(e) => setYarim(e.target.checked)} />
            {' '}Yarım gün (arife)
          </label>
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            Yarım tatil izin hesabında 0,5 gün sayılır ve o gün planlı sürenin
            yarısı beklenir.
          </p>
        </div>
        {isSuper && (
          <div className="field">
            <label>
              <input type="checkbox" checked={tumMagazalar}
                onChange={(e) => setTumMagazalar(e.target.checked)} />
              {' '}Tüm mağazalarda geçerli
            </label>
          </div>
        )}
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Ekleniyor...' : 'Ekle'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

// ---- KVKK: ham koordinat saklama suresi ----

function KvkkPanel() {
  const [durum, setDurum] = useState(null);
  const [busy, setBusy] = useState(false);

  const yukle = useCallback(() => {
    api.get('/pdks/kvkk/status', { silent: true })
      .then((r) => setDurum(r.data)).catch(() => {});
  }, []);

  useEffect(() => { yukle(); }, [yukle]);

  async function temizle() {
    if (!window.confirm(
      'Saklama süresi geçmiş kayıtların ham konum koordinatları silinecek.\n\n'
      + 'Devam kayıtları silinmez; mesafe özeti ve konum geçerliliği korunur.'
    )) return;
    setBusy(true);
    try {
      const r = await api.post('/pdks/kvkk/purge', undefined, { noToast: true });
      toast(r.data.purged > 0
        ? `${r.data.purged} kaydın koordinatı silindi`
        : 'Süresi geçmiş kayıt yok');
      yukle();
    } catch (e) {
      toast(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  if (!durum) return null;

  return (
    <div className="surface-panel">
      <div className="mo-head">
        <h3><ShieldCheck size={18} /> KVKK — Konum Verisi Saklama</h3>
        <span className="muted">Saklama süresi: {durum.retention_days} gün</span>
      </div>
      <div className="mo-figures">
        <div className="mo-figure">
          <span>Toplam devam kaydı</span>
          <strong>{durum.total_logs}</strong>
        </div>
        <div className="mo-figure">
          <span>Koordinat tutan</span>
          <strong>{durum.with_coordinates}</strong>
        </div>
        <div className="mo-figure">
          <span>Süresi geçmiş</span>
          <strong className={durum.overdue > 0 ? 'text-warning' : 'text-ok'}>
            {durum.overdue}
          </strong>
        </div>
        <div className="mo-figure">
          <span>Temizlenmiş</span>
          <strong className="text-ok">{durum.already_purged}</strong>
        </div>
      </div>
      <p className="muted" style={{ fontSize: 12, margin: '10px 0 0' }}>
        {durum.note}
      </p>
      {durum.oldest_with_coordinates && (
        <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
          Koordinat tutan en eski kayıt: {fmtDateTime(durum.oldest_with_coordinates)}
        </p>
      )}
      <p className="muted" style={{ fontSize: 11, margin: '4px 0 0' }}>
        Temizlik sunucu her soğuk başlatmada kendiliğinden çalışır; buradan elle
        de tetikleyebilirsiniz. Süre <code>PDKS_COORD_RETENTION_DAYS</code> ile
        değiştirilir.
      </p>
      <div className="actions" style={{ marginTop: 10 }}>
        <button className="btn btn-secondary" onClick={temizle}
          disabled={busy || durum.overdue === 0}>
          <ShieldCheck size={16} />
          {durum.overdue > 0 ? `${durum.overdue} kaydı temizle` : 'Temizlenecek kayıt yok'}
        </button>
      </div>
    </div>
  );
}
