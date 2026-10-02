import { useEffect, useState } from 'react';
import { Image as ImageIcon, Camera, Upload } from 'lucide-react';
import api from '../../api';
import { Modal, toast } from '../ui';
import { fmtDate, fmtDateTime, errorMessage } from '../../format';

// Personel talepleri: izin, saatlik izin, vardiya takasi/devri, haftalik OFF
// ve rapor. Devam Takibi ve Taleplerim ekranlari ile yonetici onay listesi
// ayni etiketleri, ozeti ve formu kullanir.

export const TALEP_ETIKET = {
  IZIN: 'Yıllık İzin',
  SAATLIK_IZIN: 'Saatlik İzin',
  VARDIYA_TAKAS: 'Vardiya Takası',
  VARDIYA_DEVIR: 'Vardiya Devri',
  HAFTALIK_OFF: 'Haftalık OFF',
  RAPOR: 'Rapor',
};
export const DURUM_SINIF = { PENDING: 'warning', APPROVED: 'sold', REJECTED: 'critical', CANCELLED: 'discarded' };

/// Takasta karsi tarafin onayi bekleniyor mu?
export const karsiTarafBekliyor = (r) =>
  r.type === 'VARDIYA_TAKAS' && r.status === 'PENDING' && !r.target_confirmed_at;

export function durumEtiket(r) {
  if (r.status === 'PENDING') return karsiTarafBekliyor(r) ? 'Karşı Taraf Onayı' : 'Müdür Onayında';
  return { APPROVED: 'Onaylandı', REJECTED: 'Reddedildi', CANCELLED: 'İptal' }[r.status] || r.status;
}

/// Onayla birlikte haftalik cizelgeyi degistiren turler.
export const CIZELGEYI_DEGISTIRIR = ['VARDIYA_TAKAS', 'VARDIYA_DEVIR', 'HAFTALIK_OFF', 'RAPOR'];

const GUN_KISA = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
/// 'YYYY-MM-DD' -> 'Pzt 05.10'
export function gunEtiket(t) {
  if (!t) return '—';
  const d = new Date(`${t}T00:00:00`);
  if (Number.isNaN(d.getTime())) return t;
  return `${GUN_KISA[d.getDay()]} ${t.slice(8, 10)}.${t.slice(5, 7)}`;
}

/// Talebin tek satirlik ozeti.
export function talepOzet(r) {
  switch (r.type) {
    case 'IZIN': return `${fmtDate(r.start_at)} – ${fmtDate(r.end_at)} (${r.days} gün)`;
    case 'SAATLIK_IZIN': return `${fmtDateTime(r.start_at)} · ${r.hours} saat`;
    case 'VARDIYA_TAKAS':
      return r.target_shift_date && r.target_shift_date !== r.shift_date
        ? `${gunEtiket(r.shift_date)} ↔ ${gunEtiket(r.target_shift_date)} vardiyaları`
        : `${gunEtiket(r.shift_date)} vardiyası`;
    case 'VARDIYA_DEVIR': return `${gunEtiket(r.shift_date)} vardiyası`;
    case 'HAFTALIK_OFF':
      return r.target_shift_date
        ? `OFF günü ${gunEtiket(r.target_shift_date)} → ${gunEtiket(r.shift_date)}`
        : `${gunEtiket(r.shift_date)} OFF günü`;
    case 'RAPOR':
      return r.start_at === r.end_at
        ? `${fmtDate(r.start_at)} (1 gün)`
        : `${fmtDate(r.start_at)} – ${fmtDate(r.end_at)} (${r.days} gün)`;
    default: return '';
  }
}

const bugun = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const gunEkle = (t, n) => {
  const d = new Date(`${t}T00:00:00`);
  d.setDate(d.getDate() + n);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
/// ISO haftasinin pazartesisi.
const haftaBasi = (t) => {
  const d = new Date(`${t}T00:00:00`);
  return gunEkle(t, -((d.getDay() + 6) % 7));
};

/// Rapor fotografini tarayicida kucultur: uzun kenar 1280 px, JPEG. Telefon
/// fotolari 3-5 MB geliyor; sunucu 3 MB ustunu reddediyor.
function raporKucult(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('Dosya okunamadı'));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error('Görsel açılamadı'));
      img.onload = () => {
        const oran = Math.min(1, 1280 / Math.max(img.width, img.height));
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(img.width * oran);
        canvas.height = Math.round(img.height * oran);
        canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
        let q = 0.72;
        let url = canvas.toDataURL('image/jpeg', q);
        while (url.length > 900000 && q > 0.35) {
          q -= 0.1;
          url = canvas.toDataURL('image/jpeg', q);
        }
        resolve(url);
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

/// Rapor gorselini acar. Gorsel listede tasinmaz, ayri uctan istenir.
export function RaporGorselModal({ talep, onClose }) {
  const [url, setUrl] = useState(null);
  const [hata, setHata] = useState('');
  useEffect(() => {
    api.get(`/pdks/requests/${talep.id}/attachment`, { busyMessage: 'Rapor yükleniyor...' })
      .then((r) => setUrl(r.data.data_url))
      .catch((e) => setHata(errorMessage(e)));
  }, [talep.id]);
  return (
    <Modal title="Rapor Görseli" onClose={onClose} wide>
      <p className="muted" style={{ marginTop: 0 }}>
        {talep.full_name ? `${talep.full_name} · ` : ''}{talepOzet(talep)}
      </p>
      {hata && <div className="alert error">{hata}</div>}
      {url && <img src={url} alt="Rapor" className="rapor-gorsel" />}
    </Modal>
  );
}

/// Yeni talep formu.
export function TalepModal({ bakiye, baslangicTuru = 'IZIN', onClose, onDone }) {
  const [tur, setTur] = useState(baslangicTuru);
  const [baslangic, setBaslangic] = useState('');
  const [bitis, setBitis] = useState('');
  const [saatBas, setSaatBas] = useState('');
  const [saatBit, setSaatBit] = useState('');
  const [vardiyaTarih, setVardiyaTarih] = useState('');
  const [hedefId, setHedefId] = useState('');
  const [ayniGun, setAyniGun] = useState(true);
  const [hedefTarih, setHedefTarih] = useState('');
  const [offTarih, setOffTarih] = useState(() => gunEkle(bugun(), 1));
  const [eskiOff, setEskiOff] = useState('');
  const [raporBas, setRaporBas] = useState(bugun);
  const [raporBit, setRaporBit] = useState(bugun);
  const [rapor, setRapor] = useState(null);
  const [gerekce, setGerekce] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const [atamalar, setAtamalar] = useState([]);
  const [meslektaslar, setMeslektaslar] = useState([]);

  // Takas ve OFF icin onumuzdeki vardiyalar; gun listeden secilir.
  useEffect(() => {
    if (!['VARDIYA_TAKAS', 'VARDIYA_DEVIR', 'HAFTALIK_OFF'].includes(tur)) return;
    api.get(`/pdks/assignments?from=${bugun()}&to=${gunEkle(bugun(), 60)}`, { silent: true })
      .then((r) => setAtamalar(r.data)).catch(() => {});
    if (tur === 'VARDIYA_TAKAS') {
      api.get('/pdks/requests/colleagues', { silent: true })
        .then((r) => setMeslektaslar(r.data)).catch(() => {});
    }
  }, [tur]);

  const vardiyalarim = atamalar.filter((a) => !a.is_day_off);
  const haftaninOfflari = atamalar.filter((a) => a.is_day_off && a.work_date !== offTarih
    && haftaBasi(a.work_date) === haftaBasi(offTarih));

  async function fotoSec(e) {
    const file = e.target.files && e.target.files[0];
    e.target.value = '';
    if (!file) return;
    if (!/^image\//.test(file.type)) { setErr('Lütfen bir görsel seçin'); return; }
    try {
      setRapor(await raporKucult(file));
      setErr('');
    } catch (er) {
      setErr(er.message);
    }
  }

  async function gonder(e) {
    e.preventDefault();
    setErr('');
    const istegeBagli = tur === 'HAFTALIK_OFF' || tur === 'RAPOR';
    const govde = { type: tur, reason: gerekce.trim() };
    if (!govde.reason && !istegeBagli) { setErr('Gerekçe zorunludur'); return; }
    if (tur === 'IZIN') {
      if (!baslangic || !bitis) { setErr('Tarih aralığı seçin'); return; }
      govde.start_at = baslangic;
      govde.end_at = bitis;
    } else if (tur === 'SAATLIK_IZIN') {
      if (!saatBas || !saatBit) { setErr('Saat aralığı seçin'); return; }
      // datetime-local yerel saat verir; ISO'ya cevrilir.
      govde.start_at = new Date(saatBas).toISOString();
      govde.end_at = new Date(saatBit).toISOString();
    } else if (tur === 'VARDIYA_TAKAS' || tur === 'VARDIYA_DEVIR') {
      if (!vardiyaTarih) { setErr('Bir vardiya seçin'); return; }
      govde.shift_date = vardiyaTarih;
      if (tur === 'VARDIYA_TAKAS') {
        if (!hedefId) { setErr('Takas yapılacak partneri seçin'); return; }
        govde.target_user_id = Number(hedefId);
        if (!ayniGun) {
          if (!hedefTarih) { setErr('Partnerin vardiya gününü seçin'); return; }
          govde.target_shift_date = hedefTarih;
        }
      }
    } else if (tur === 'HAFTALIK_OFF') {
      if (!offTarih) { setErr('OFF gününü seçin'); return; }
      govde.shift_date = offTarih;
      if (eskiOff) govde.target_shift_date = eskiOff;
    } else if (tur === 'RAPOR') {
      if (!raporBas || !raporBit) { setErr('Rapor tarihlerini seçin'); return; }
      if (raporBit < raporBas) { setErr('Bitiş tarihi başlangıçtan önce olamaz'); return; }
      if (!rapor) { setErr('Rapor görselini galeriden seçin ya da fotoğrafını çekin'); return; }
      govde.start_at = raporBas;
      govde.end_at = raporBit;
      govde.attachment = rapor;
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

  const ipucu = { fontSize: 'var(--fs-label)', margin: '4px 0 0' };

  return (
    <Modal title="Yeni Talep" onClose={onClose} busy={busy}>
      <form onSubmit={gonder}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Talep Türü</label>
          <select value={tur} onChange={(e) => { setTur(e.target.value); setErr(''); }}>
            <option value="IZIN">Yıllık İzin</option>
            <option value="SAATLIK_IZIN">Saatlik İzin</option>
            <option value="VARDIYA_TAKAS">Vardiya Takası</option>
            <option value="HAFTALIK_OFF">Haftalık OFF</option>
            <option value="RAPOR">Rapor</option>
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
              <p className="muted" style={ipucu}>Kalan hakkınız {bakiye.leave.remaining_days} gün.</p>
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
              <p className="muted" style={ipucu}>Aynı gün içinde ve en fazla 12 saat olabilir.</p>
            </div>
          </>
        )}

        {tur === 'VARDIYA_TAKAS' && (
          <>
            <div className="field">
              <label>Devredeceğim Vardiya</label>
              <select value={vardiyaTarih} onChange={(e) => setVardiyaTarih(e.target.value)}>
                <option value="">Seçin…</option>
                {vardiyalarim.map((a) => (
                  <option key={`${a.work_date}-${a.shift_id}`} value={a.work_date}>
                    {gunEtiket(a.work_date)} · {a.shift_name || 'Vardiya'} {a.start_time}–{a.end_time}
                  </option>
                ))}
              </select>
              {vardiyalarim.length === 0 && (
                <p className="muted" style={ipucu}>Önümüzdeki günlerde size atanmış bir vardiya yok.</p>
              )}
            </div>
            <div className="field">
              <label>Takas Yapılacak Partner</label>
              <select value={hedefId} onChange={(e) => setHedefId(e.target.value)}>
                <option value="">Seçin…</option>
                {meslektaslar.map((m) => <option key={m.id} value={m.id}>{m.full_name}</option>)}
              </select>
            </div>
            <label className="check-row">
              <input type="checkbox" checked={ayniGun} onChange={(e) => setAyniGun(e.target.checked)} />
              <span>Aynı gün içinde takas</span>
            </label>
            {!ayniGun && (
              <div className="field">
                <label>Partnerin Vardiya Günü</label>
                <input type="date" min={bugun()} value={hedefTarih} onChange={(e) => setHedefTarih(e.target.value)} />
              </div>
            )}
            <p className="muted" style={ipucu}>
              Önce partneriniz onaylar, ardından mağaza müdürü. Onayla birlikte haftalık
              çizelge otomatik güncellenir.
            </p>
          </>
        )}

        {tur === 'HAFTALIK_OFF' && (
          <>
            <div className="field">
              <label>İstediğim OFF Günü</label>
              <input type="date" min={bugun()} value={offTarih}
                onChange={(e) => { setOffTarih(e.target.value); setEskiOff(''); }} />
            </div>
            <div className="field">
              <label>Bu Haftaki Mevcut OFF Günüm</label>
              <select value={eskiOff} onChange={(e) => setEskiOff(e.target.value)}>
                <option value="">Değiştirme, yalnızca OFF ekle</option>
                {haftaninOfflari.map((a) => (
                  <option key={a.work_date} value={a.work_date}>{gunEtiket(a.work_date)} · OFF</option>
                ))}
              </select>
              <p className="muted" style={ipucu}>Seçerseniz iki gün yer değiştirir.</p>
            </div>
          </>
        )}

        {tur === 'RAPOR' && (
          <>
            <div className="field">
              <label>Rapor Başlangıcı</label>
              <input type="date" value={raporBas} onChange={(e) => setRaporBas(e.target.value)} />
            </div>
            <div className="field">
              <label>Rapor Bitişi</label>
              <input type="date" value={raporBit} onChange={(e) => setRaporBit(e.target.value)} />
            </div>
            <div className="field">
              <label>Rapor Görseli</label>
              {rapor && <img src={rapor} alt="Rapor önizleme" className="rapor-onizleme" />}
              <div className="row-actions">
                <label className="btn btn-secondary">
                  <Upload size={16} /> Galeriden
                  <input type="file" accept="image/*" onChange={fotoSec} hidden />
                </label>
                {/* capture: telefonda dogrudan kamerayi acar. */}
                <label className="btn btn-secondary">
                  <Camera size={16} /> Fotoğraf Çek
                  <input type="file" accept="image/*" capture="environment" onChange={fotoSec} hidden />
                </label>
              </div>
            </div>
          </>
        )}

        <div className="field">
          <label>{tur === 'HAFTALIK_OFF' || tur === 'RAPOR' ? 'Açıklama (isteğe bağlı)' : 'Gerekçe'}</label>
          <input value={gerekce} onChange={(e) => setGerekce(e.target.value)} />
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

/// Personelin talep listesi: kendi talepleri + karsi taraf oldugu takaslar.
export function TalepListesi({ talepler, user, onChange }) {
  const [gorsel, setGorsel] = useState(null);

  async function islem(yol, mesaj) {
    try {
      await api.post(yol, undefined, { successMessage: mesaj });
      onChange();
    } catch { /* bildirim api katmaninda */ }
  }

  if (talepler.length === 0) return <p className="empty">Henüz talebiniz yok.</p>;
  return (
    <>
      <div className="table-wrap">
        <table className="responsive">
          <thead>
            <tr><th>Tür</th><th>Detay</th><th>Durum</th><th>Karar</th><th>İşlem</th></tr>
          </thead>
          <tbody>
            {talepler.map((r) => {
              const benim = Number(r.user_id) === Number(user.id);
              const hedefBenim = Number(r.target_user_id) === Number(user.id);
              return (
                <tr key={r.id}>
                  <td data-label="Tür"><strong>{TALEP_ETIKET[r.type] || r.type}</strong></td>
                  <td data-label="Detay">
                    {talepOzet(r)}
                    {r.type === 'VARDIYA_TAKAS' && (
                      <div className="muted" style={{ fontSize: 'var(--fs-label)' }}>
                        {benim ? `Takas: ${r.target_name || '—'}` : `Talep eden: ${r.full_name || '—'}`}
                      </div>
                    )}
                    {r.reason && <div className="muted" style={{ fontSize: 'var(--fs-label)' }}>{r.reason}</div>}
                  </td>
                  <td data-label="Durum">
                    <span className={`badge ${DURUM_SINIF[r.status]}`}>{durumEtiket(r)}</span>
                  </td>
                  <td data-label="Karar" className="muted" style={{ fontSize: 'var(--fs-label)' }}>
                    {r.manager_name || '-'}
                    {r.decision_note && <div>{r.decision_note}</div>}
                  </td>
                  <td data-label="İşlem">
                    <div className="row-actions">
                      {r.has_attachment && (
                        <button className="btn btn-sm btn-secondary" onClick={() => setGorsel(r)}>
                          <ImageIcon size={14} /> Raporu Gör
                        </button>
                      )}
                      {karsiTarafBekliyor(r) && hedefBenim && (
                        <button className="btn btn-sm btn-primary"
                          onClick={() => islem(`/pdks/requests/${r.id}/confirm`, 'Takas onaylandı, müdür onayına gönderildi')}>
                          Takası Onayla
                        </button>
                      )}
                      {r.status === 'PENDING' && benim && (
                        <button className="btn btn-sm btn-secondary"
                          onClick={() => islem(`/pdks/requests/${r.id}/cancel`, 'Talep geri alındı')}>
                          Geri Al
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {gorsel && <RaporGorselModal talep={gorsel} onClose={() => setGorsel(null)} />}
    </>
  );
}
