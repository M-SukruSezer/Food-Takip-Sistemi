import { useCallback, useEffect, useState } from 'react';
import {
  CalendarRange, ChevronLeft, ChevronRight, FileText, Users, Coffee, Moon,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, toast } from '../components/ui';
import { errorMessage, fmtDate } from '../format';
import { PDF_FONT, pdfFontKur } from '../pdfFont';

// Toplu vardiya cizelgesi: magazanin TUM ekibi bir arada, haftalik ya da
// gunluk. Barista dahil herkes goruyor — kimin ne zaman calistigi ekibin
// gunluk olarak ihtiyac duydugu bilgi. Duzenleme Devam Yonetimi'nde.

const GUN_KISA = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];

// Vardiya kategorileri. Renk TEK BASINA bilgi tasimasin diye her kategorinin
// kisa bir etiketi de var (erisilebilirlik: renk korlugu ve yazdirma).
// Siniflandirma sunucuda, 4857 sayili Kanun'a gore yapiliyor.
const KATEGORI = {
  sabah: { etiket: 'Sabah', sinif: 'k-sabah' },
  gunduz: { etiket: 'Gündüz', sinif: 'k-gunduz' },
  aksam: { etiket: 'Akşam', sinif: 'k-aksam' },
  gece: { etiket: 'Gece', sinif: 'k-gece' },
};
const GUN_UZUN = ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'];

const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const gunAdi = (tarih, uzun = false) =>
  (uzun ? GUN_UZUN : GUN_KISA)[new Date(`${tarih}T00:00:00Z`).getUTCDay()];

/// Verilen tarihin icinde bulundugu haftanin PAZARTESI'si.
/// Turkiye'de is haftasi pazartesi basliyor; getDay() pazari 0 verdigi icin
/// pazar gunu bir onceki haftaya cekilmeli.
function haftaBasi(d) {
  const x = new Date(d);
  const gun = x.getDay();
  x.setDate(x.getDate() - (gun === 0 ? 6 : gun - 1));
  x.setHours(0, 0, 0, 0);
  return x;
}

const saat = (dk) => {
  if (!dk) return '-';
  const s = Math.floor(dk / 60);
  const m = dk % 60;
  return m ? `${s}s ${m}dk` : `${s}s`;
};

export default function Roster() {
  const { user } = useAuth();
  const [mod, setMod] = useState('hafta');
  const [anchor, setAnchor] = useState(() => haftaBasi(new Date()));
  const [gun, setGun] = useState(() => iso(new Date()));
  const [magazalar, setMagazalar] = useState([]);
  const [storeId, setStoreId] = useState('');
  const [veri, setVeri] = useState(null);
  const [hata, setHata] = useState('');
  const [disa, setDisa] = useState(false);
  const [vardiyalar, setVardiyalar] = useState([]);
  const [hucre, setHucre] = useState(null);

  // Cok magazali roller icin magaza secici; tek magazalida gereksiz.
  const cokMagaza = ['super_admin', 'operations_manager', 'regional_manager'].includes(user.role);

  useEffect(() => {
    if (!cokMagaza) return;
    api.get('/stores', { silent: true })
      .then((r) => setMagazalar(r.data.filter((m) => m.active)))
      .catch(() => {});
  }, [cokMagaza]);

  const from = mod === 'hafta' ? iso(anchor) : gun;
  const to = mod === 'hafta'
    ? iso(new Date(anchor.getTime() + 6 * 86400000))
    : gun;

  const yukle = useCallback(() => {
    const m = storeId ? `&storeId=${storeId}` : '';
    api.get(`/pdks/roster?from=${from}&to=${to}${m}`)
      .then((r) => { setVeri(r.data); setHata(''); })
      .catch((e) => { setVeri(null); setHata(errorMessage(e)); });
  }, [from, to, storeId]);

  useEffect(() => { yukle(); }, [yukle]);

  // Hucre duzenlemesi icin atanabilir vardiyalar. Yalnizca duzenleme yetkisi
  // olanlar icin cekiliyor; barista bu listeyi hic istemiyor.
  useEffect(() => {
    if (!veri || !veri.can_edit) return;
    api.get('/pdks/shifts', { silent: true })
      .then((r) => setVardiyalar(r.data.filter((v) => v.active)))
      .catch(() => {});
  }, [veri && veri.can_edit]);

  function kaydir(yon) {
    if (mod === 'hafta') {
      setAnchor(new Date(anchor.getTime() + yon * 7 * 86400000));
    } else {
      setGun(iso(new Date(new Date(`${gun}T00:00:00`).getTime() + yon * 86400000)));
    }
  }

  async function pdfAktar() {
    if (!veri || veri.people.length === 0) { toast('Dışa aktarılacak kayıt yok'); return; }
    setDisa(true);
    try {
      const { jsPDF } = await import('jspdf');
      const { default: autoTable } = await import('jspdf-autotable');
      // 7 gun + isim dikey sayfaya sigmiyor.
      const doc = new jsPDF({ orientation: 'landscape' });
      // Turkce karakterler icin gomulu yazi tipi; basarisiz olursa uyarilir.
      const fontTamam = await pdfFontKur(doc);
      if (!fontTamam) toast('Yazı tipi yüklenemedi, Türkçe karakterler bozuk çıkabilir');
      const f = fontTamam ? PDF_FONT : 'helvetica';

      doc.setFont(f, 'bold');
      doc.setFontSize(15);
      doc.text('Haftalık Vardiya Planı', 14, 14);
      doc.setFont(f, 'normal');
      doc.setFontSize(9);
      const magazaAdi = veri.store || (magazalar.find((m) => String(m.id) === String(storeId)) || {}).name || '';
      doc.text(`${magazaAdi}${magazaAdi ? ' · ' : ''}${fmtDate(veri.from)} – ${fmtDate(veri.to)}`, 14, 20);

      const basliklar = ['Personel', ...veri.dates.map((d) => `${gunAdi(d)}\n${d.slice(8)}.${d.slice(5, 7)}`), 'Planlı'];
      const satirlar = veri.people.map((p) => [
        p.user.full_name,
        ...veri.dates.map((d) => hucreMetin(p.cells[d], veri.holidays[d])),
        saat(p.planned_minutes),
      ]);
      const toplam = ['TOPLAM',
        ...veri.dates.map((d) => `${veri.totals[d].working} kişi`),
        saat(veri.people.reduce((a, p) => a + p.planned_minutes, 0))];

      autoTable(doc, {
        head: [basliklar],
        body: [...satirlar, toplam],
        startY: 25,
        styles: { font: f, fontSize: 7, cellPadding: 2, valign: 'middle' },
        headStyles: { font: f, fontStyle: 'bold', fontSize: 7, fillColor: [225, 228, 232], textColor: 20 },
        columnStyles: { 0: { cellWidth: 42, halign: 'left' } },
        didParseCell: (data) => {
          if (data.row.index === satirlar.length) data.cell.styles.fontStyle = 'bold';
        },
      });

      doc.setFontSize(7);
      doc.text(
        'Hafta tatili "HT", resmi tatil "RT" olarak işaretlenir. Gece vardiyası saatin yanında ")" ile gösterilir.',
        14, doc.lastAutoTable.finalY + 6,
      );
      doc.text(
        'Planlı süreler NET çalışmadır: ara dinlenmesi (4857 m.68) düşülmüştür.',
        14, doc.lastAutoTable.finalY + 10,
      );
      doc.save(`vardiya-plani-${veri.from}.pdf`);
    } catch (e) {
      toast('Dışa aktarılamadı');
    } finally {
      setDisa(false);
    }
  }

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><CalendarRange size={20} /> Vardiya Çizelgesi</h2>
        <div className="actions">
          <div className="stock-tabs">
            <button className={mod === 'hafta' ? 'active' : ''} onClick={() => setMod('hafta')}>Haftalık</button>
            <button className={mod === 'gun' ? 'active' : ''} onClick={() => setMod('gun')}>Günlük</button>
          </div>
          {veri && veri.can_edit && mod === 'hafta' && (
            <button className="btn btn-secondary" disabled={disa} onClick={pdfAktar}>
              <FileText size={16} /> PDF
            </button>
          )}
        </div>
      </div>

      <div className="surface-panel">
        <div className="filters">
          <button className="btn btn-sm btn-secondary" onClick={() => kaydir(-1)}>
            <ChevronLeft size={16} /> Önceki
          </button>
          <strong style={{ minWidth: 190, textAlign: 'center' }}>
            {mod === 'hafta'
              ? `${fmtDate(from)} – ${fmtDate(to)}`
              : `${fmtDate(gun)} ${gunAdi(gun, true)}`}
          </strong>
          <button className="btn btn-sm btn-secondary" onClick={() => kaydir(1)}>
            Sonraki <ChevronRight size={16} />
          </button>
          {cokMagaza && (
            <label>Mağaza
              <select value={storeId} onChange={(e) => setStoreId(e.target.value)}>
                <option value="">Tümü</option>
                {magazalar.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
              </select>
            </label>
          )}
        </div>
      </div>

      {hata && <div className="alert error">{hata}</div>}

      {veri && veri.people.length === 0 && (
        <div className="surface-panel"><p className="empty">Personel bulunamadı.</p></div>
      )}

      {veri && veri.people.length > 0 && (
        mod === 'hafta'
          ? (
            <HaftaTablosu
              veri={veri}
              onHucre={veri.can_edit ? (kisi, gun) => setHucre({ kisi, gun }) : null}
            />
          )
          : <GunListesi veri={veri} gun={gun} />
      )}

      {hucre && (
        <HucreModal
          kisi={hucre.kisi}
          gun={hucre.gun}
          mevcut={hucre.kisi.cells[hucre.gun] || []}
          vardiyalar={vardiyalar}
          onClose={() => setHucre(null)}
          onDone={() => { setHucre(null); yukle(); }}
        />
      )}
    </div>
  );
}

/// Tek hucre duzenlemesi: bir personelin bir gunu.
///
/// Sunucuya TEK istek gidiyor (PUT /pdks/assignments/cell): "bu gunu su hale
/// getir". Istemcide once silip sonra eklemek yarim kalabilirdi.
function HucreModal({ kisi, gun, mevcut, vardiyalar, onClose, onDone }) {
  const tatilVar = mevcut.some((c) => c.is_day_off);
  const mevcutId = mevcut.find((c) => !c.is_day_off)?.shift_id ?? '';
  const [secim, setSecim] = useState(tatilVar ? 'HT' : mevcutId ? String(mevcutId) : '');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  async function kaydet() {
    setErr('');
    setBusy(true);
    try {
      await api.put('/pdks/assignments/cell', {
        user_id: kisi.user.id,
        work_date: gun,
        is_day_off: secim === 'HT',
        shift_id: secim === 'HT' || secim === '' ? null : Number(secim),
      }, { successMessage: 'Plan güncellendi' });
      onDone();
    } catch (e) {
      setErr(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title={`${kisi.user.full_name} — ${fmtDate(gun)} ${gunAdi(gun, true)}`}
      onClose={onClose}
    >
      <div className="form-grid">
        {err && <div className="alert error">{err}</div>}
        <div className="cell-options">
          {vardiyalar.map((v) => {
            const uy = vardiyaUyari(v);
            return (
              <label key={v.id} className={`cell-option ${secim === String(v.id) ? 'secili' : ''}`}>
                <input
                  type="radio"
                  name="vardiya"
                  value={String(v.id)}
                  checked={secim === String(v.id)}
                  onChange={(e) => setSecim(e.target.value)}
                />
                <span className="cell-option-body">
                  <strong>{v.name}</strong>
                  <span className="muted">
                    {(v.start_time || '').slice(0, 5)}–{(v.end_time || '').slice(0, 5)}
                    {' · '}net {saat(netDakika(v))}
                    {v.break_duration_minutes > 0 && ` · ${v.break_duration_minutes} dk mola`}
                  </span>
                  {uy && <span className="cell-option-uyari">{uy}</span>}
                </span>
              </label>
            );
          })}
          <label className={`cell-option ${secim === 'HT' ? 'secili' : ''}`}>
            <input
              type="radio" name="vardiya" value="HT"
              checked={secim === 'HT'}
              onChange={(e) => setSecim(e.target.value)}
            />
            <span className="cell-option-body">
              <strong>Hafta tatili</strong>
              <span className="muted">Planlı süre sayılmaz</span>
            </span>
          </label>
          <label className={`cell-option ${secim === '' ? 'secili' : ''}`}>
            <input
              type="radio" name="vardiya" value=""
              checked={secim === ''}
              onChange={(e) => setSecim(e.target.value)}
            />
            <span className="cell-option-body">
              <strong>Boş bırak</strong>
              <span className="muted">Atama silinir</span>
            </span>
          </label>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="button" className="btn btn-primary" disabled={busy} onClick={kaydet}>
            Kaydet
          </button>
        </div>
      </div>
    </Modal>
  );
}

/// Vardiya listesinde gosterilecek kisa yasal uyari. Sunucudaki kuralin
/// istemci karsiligi; yalnizca SECIM ekraninda on bilgi icin, cizelgedeki
/// uyarilar sunucudan geliyor.
function vardiyaUyari(v) {
  const b = (v.start_time || '').slice(0, 5);
  const e = (v.end_time || '').slice(0, 5);
  if (!b || !e) return null;
  const dk = (x) => Number(x.slice(0, 2)) * 60 + Number(x.slice(3, 5));
  const bs = dk(b);
  const bt = dk(e) > bs ? dk(e) : dk(e) + 1440;
  const sure = bt - bs;
  if (sure > 11 * 60) return '11 saat aşımı (m.63)';
  const yasal = sure <= 240 ? 15 : sure <= 450 ? 30 : 60;
  if ((Number(v.break_duration_minutes) || 0) < yasal) return `mola en az ${yasal} dk (m.68)`;
  return null;
}

/// Net calisma: mola dusulmus. Sunucudaki netDakika ile ayni kural.
function netDakika(v) {
  const b = (v.start_time || '').slice(0, 5);
  const e = (v.end_time || '').slice(0, 5);
  if (!b || !e) return 0;
  const dk = (x) => Number(x.slice(0, 2)) * 60 + Number(x.slice(3, 5));
  const bs = dk(b);
  const sure = (dk(e) > bs ? dk(e) : dk(e) + 1440) - bs;
  const yasal = sure <= 240 ? 15 : sure <= 450 ? 30 : 60;
  const tanimli = Number(v.break_duration_minutes) || 0;
  return Math.max(0, sure - (tanimli > 0 ? Math.min(tanimli, yasal) : 0));
}

/// Hucrenin metin karsiligi. PDF ve tablo ayni gosterimi kullansin diye
/// tek fonksiyon.
function hucreMetin(hucreler, tatil) {
  if (tatil && tatil.half !== true) return 'RT';
  if (!hucreler || hucreler.length === 0) return '-';
  if (hucreler.some((c) => c.is_day_off)) return 'HT';
  return hucreler
    .map((c) => `${(c.start_time || '').slice(0, 5)}-${(c.end_time || '').slice(0, 5)}${c.crosses_midnight ? ')' : ''}`)
    .join(' / ');
}

function HaftaTablosu({ veri, onHucre }) {
  return (
    <>
      <div className="card table-card">
        <div className="table-wrap">
          <table className="roster">
            <thead>
              <tr>
                <th className="roster-name">Personel</th>
                {veri.dates.map((d) => {
                  const t = veri.holidays[d];
                  return (
                    <th key={d} className={t ? 'roster-holiday' : ''} title={t ? t.name : ''}>
                      <span className="roster-dow">{gunAdi(d)}</span>
                      <span className="roster-day">{d.slice(8)}.{d.slice(5, 7)}</span>
                    </th>
                  );
                })}
                <th>Planlı</th>
              </tr>
            </thead>
            <tbody>
              {veri.people.map((p) => (
                <tr key={p.user.id}>
                  <td className="roster-name"><strong>{p.user.full_name}</strong></td>
                  {veri.dates.map((d) => (
                    <Hucre
                      key={d}
                      hucreler={p.cells[d]}
                      tatil={veri.holidays[d]}
                      duzenle={onHucre ? () => onHucre(p, d) : null}
                    />
                  ))}
                  <td className="roster-total">{saat(p.planned_minutes)}</td>
                </tr>
              ))}
              <tr className="roster-foot">
                <td className="roster-name"><strong>Çalışan sayısı</strong></td>
                {veri.dates.map((d) => (
                  <td key={d}>
                    <strong>{veri.totals[d].working}</strong>
                    {veri.totals[d].unassigned > 0 && (
                      <span className="muted"> / {veri.totals[d].unassigned} boş</span>
                    )}
                  </td>
                ))}
                <td className="roster-total">
                  <strong>{saat(veri.people.reduce((a, p) => a + p.planned_minutes, 0))}</strong>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <p className="muted" style={{ fontSize: 12 }}>
        <strong>HT</strong> hafta tatili · <strong>RT</strong> resmi tatil ·
        {' '}<Moon size={12} style={{ verticalAlign: -2 }} /> gece vardiyası (ertesi güne sarkar)
        <br />
        Planlı süreler <strong>net çalışmadır</strong>: ara dinlenmesi düşülmüştür (4857 m.68).
        Kırmızı çerçeveli hücre yasal sınır uyarısı taşır.
      </p>
    </>
  );
}

function Hucre({ hucreler, tatil, duzenle }) {
  const tamTatil = tatil && tatil.half !== true;
  const bos = !hucreler || hucreler.length === 0;
  const tatilKaydi = !bos && hucreler.some((c) => c.is_day_off);
  // Yasal uyari tasiyan hucre kirmizi cerceve aliyor; sebep title'da ve
  // kisa etiket olarak hucrede yaziyor.
  const uyarilar = bos ? [] : hucreler.flatMap((c) => c.warnings || []);

  let govde;
  if (tamTatil) {
    govde = <span className="roster-rt">RT</span>;
  } else if (tatilKaydi) {
    govde = <span className="roster-ht">HT</span>;
  } else if (bos) {
    govde = <span className="roster-bos">{duzenle ? '+' : '-'}</span>;
  } else {
    govde = hucreler.map((c, i) => {
      const k = KATEGORI[c.category] || null;
      return (
        <span className={`roster-shift ${k ? k.sinif : ''}`} key={i}>
          <span className="roster-saat">
            {(c.start_time || '').slice(0, 5)}–{(c.end_time || '').slice(0, 5)}
            {c.crosses_midnight && <Moon size={10} />}
          </span>
          {k && <span className="roster-kat">{k.etiket}</span>}
        </span>
      );
    });
  }

  const baslik = tamTatil ? tatil.name
    : uyarilar.length ? uyarilar.map((u) => u.aciklama).join('\n')
    : duzenle ? 'Vardiya atamak için tıklayın' : undefined;

  const sinif = [
    'roster-cell',
    tamTatil ? 'holiday' : '',
    tatilKaydi ? 'off' : '',
    bos && !tamTatil ? 'empty-cell' : '',
    uyarilar.length ? 'uyari' : '',
    duzenle ? 'duzenlenebilir' : '',
  ].filter(Boolean).join(' ');

  // Duzenlenebilir hucre gercek bir dugme: klavyeyle de erisilebilsin.
  if (duzenle && !tamTatil) {
    return (
      <td className={sinif}>
        <button type="button" className="roster-hucre-btn" onClick={duzenle} title={baslik}>
          {govde}
          {uyarilar.length > 0 && (
            <span className="roster-uyari">{uyarilar[0].etiket}</span>
          )}
        </button>
      </td>
    );
  }
  return (
    <td className={sinif} title={baslik}>
      {govde}
      {uyarilar.length > 0 && <span className="roster-uyari">{uyarilar[0].etiket}</span>}
    </td>
  );
}

function GunListesi({ veri, gun }) {
  const tatil = veri.holidays[gun];
  const calisan = veri.people.filter((p) => (p.cells[gun] || []).some((c) => !c.is_day_off));
  const tatilde = veri.people.filter((p) => (p.cells[gun] || []).some((c) => c.is_day_off));
  const bos = veri.people.filter((p) => (p.cells[gun] || []).length === 0);

  return (
    <>
      {tatil && (
        <div className="alert warning">
          {tatil.name}{tatil.half ? ' (yarım gün)' : ''} — resmi tatil.
        </div>
      )}
      <div className="surface-panel mo-figures">
        <div className="mo-figure"><span>Çalışan</span><strong>{calisan.length}</strong></div>
        <div className="mo-figure"><span>Hafta tatili</span><strong>{tatilde.length}</strong></div>
        <div className="mo-figure"><span>Atanmamış</span><strong>{bos.length}</strong></div>
        <div className="mo-figure"><span>Planlı süre</span><strong>{saat(veri.totals[gun] ? veri.totals[gun].minutes : 0)}</strong></div>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Personel</th><th>Vardiya</th><th>Saat</th><th>Mola</th><th>Süre</th></tr>
            </thead>
            <tbody>
              {calisan.length === 0 && (
                <tr><td data-label="" colSpan="5"><p className="empty">Bu gün çalışan personel yok.</p></td></tr>
              )}
              {calisan.map((p) => (p.cells[gun] || []).filter((c) => !c.is_day_off).map((c, i) => (
                <tr key={`${p.user.id}-${i}`}>
                  <td data-label="Personel"><strong>{p.user.full_name}</strong></td>
                  <td data-label="Vardiya">{c.shift_name || '-'}</td>
                  <td data-label="Saat">
                    {(c.start_time || '').slice(0, 5)}–{(c.end_time || '').slice(0, 5)}
                    {c.crosses_midnight && <span className="badge warning" style={{ marginLeft: 6 }}>gece</span>}
                  </td>
                  <td data-label="Mola">
                    {c.break_duration_minutes ? <><Coffee size={13} /> {c.break_duration_minutes} dk</> : '-'}
                  </td>
                  <td data-label="Süre">{saat(c.minutes)}</td>
                </tr>
              )))}
            </tbody>
          </table>
        </div>
      </div>

      {(tatilde.length > 0 || bos.length > 0) && (
        <div className="surface-panel">
          {tatilde.length > 0 && (
            <p style={{ margin: '0 0 6px' }}>
              <Users size={14} /> <strong>Hafta tatili:</strong>{' '}
              <span className="muted">{tatilde.map((p) => p.user.full_name).join(', ')}</span>
            </p>
          )}
          {bos.length > 0 && (
            <p style={{ margin: 0 }}>
              <Users size={14} /> <strong>Vardiya atanmamış:</strong>{' '}
              <span className="muted">{bos.map((p) => p.user.full_name).join(', ')}</span>
            </p>
          )}
        </div>
      )}
    </>
  );
}
