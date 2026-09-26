import { useCallback, useEffect, useState } from 'react';
import {
  CalendarRange, ChevronLeft, ChevronRight, FileText, Users, Coffee, Moon,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { toast } from '../components/ui';
import { errorMessage, fmtDate } from '../format';
import { PDF_FONT, pdfFontKur } from '../pdfFont';

// Toplu vardiya cizelgesi: magazanin TUM ekibi bir arada, haftalik ya da
// gunluk. Barista dahil herkes goruyor — kimin ne zaman calistigi ekibin
// gunluk olarak ihtiyac duydugu bilgi. Duzenleme Devam Yonetimi'nde.

const GUN_KISA = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
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
          ? <HaftaTablosu veri={veri} />
          : <GunListesi veri={veri} gun={gun} />
      )}
    </div>
  );
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

function HaftaTablosu({ veri }) {
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
                  {veri.dates.map((d) => <Hucre key={d} hucreler={p.cells[d]} tatil={veri.holidays[d]} />)}
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
      </p>
    </>
  );
}

function Hucre({ hucreler, tatil }) {
  const tamTatil = tatil && tatil.half !== true;
  if (tamTatil) return <td className="roster-cell holiday" title={tatil.name}>RT</td>;
  if (!hucreler || hucreler.length === 0) return <td className="roster-cell empty-cell">-</td>;
  if (hucreler.some((c) => c.is_day_off)) return <td className="roster-cell off">HT</td>;
  return (
    <td className="roster-cell">
      {hucreler.map((c, i) => (
        <span className="roster-shift" key={i}>
          {(c.start_time || '').slice(0, 5)}–{(c.end_time || '').slice(0, 5)}
          {c.crosses_midnight && <Moon size={11} />}
        </span>
      ))}
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
