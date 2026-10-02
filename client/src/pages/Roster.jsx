import { useCallback, useEffect, useState } from 'react';
import {
  CalendarRange, ChevronLeft, ChevronRight, FileText, Users, Coffee, Save,
  RotateCcw, CheckCircle2, Pencil, Trash2, StickyNote, Plus,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, Confirm, toast } from '../components/ui';
import { SwipeRow } from '../components/actions';
import { errorMessage, fmtDate, fmtDateTime } from '../format';
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
  kapanis: { etiket: 'Kapanış', sinif: 'k-kapanis' },
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

/// Kisinin planli NET suresi; bekleyen degisiklikler DAHIL.
///
/// Kaydetmeden once toplamin degismesi gerekiyor, aksi halde yonetici
/// yaptigi degisikligin saat etkisini kaydetmeden goremez.
function planliSure(kisi, gunler, bekleyen) {
  let toplam = 0;
  for (const d of gunler) {
    const b = bekleyen[`${kisi.user.id}|${d}`];
    if (b) {
      // Bekleyen degisiklik o gunun mevcut halini TAMAMEN degistiriyor.
      toplam += b.shift ? netDakika(b.shift) : 0;
    } else {
      toplam += (kisi.cells[d] || []).reduce((a, c) => a + (c.minutes || 0), 0);
    }
  }
  return toplam;
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
  const [paylasiyor, setPaylasiyor] = useState(false);
  const [vardiyalar, setVardiyalar] = useState([]);
  const [hucre, setHucre] = useState(null);
  // Bekleyen degisiklikler: "userId|tarih" -> hucre degisikligi.
  //
  // Her duzenlemede sunucuya gitmek yerine yerelde birikiyor ve tek "Kaydet"
  // ile gonderiliyor; yonetici tabloyu once kurup sonra onayliyor.
  const [bekleyen, setBekleyen] = useState({});
  const [kaydediyor, setKaydediyor] = useState(false);
  const [cakisma, setCakisma] = useState(null);
  // Plan notlari: magaza basina, haftalar arasinda sabit kalir.
  const [notlar, setNotlar] = useState([]);
  const [notForm, setNotForm] = useState(null); // { not? }
  const [notSil, setNotSil] = useState(null);
  const bekleyenSayi = Object.keys(bekleyen).length;

  // Paylasim, duzenleme ve disa aktarma yalnizca magaza mudurune acik.
  const magazaMuduru = user.role === 'store_manager';
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

  // Notlarin magazasi: secili magaza ya da kullanicinin kendi magazasi.
  const notMagaza = storeId || user.store_id || null;
  const notlariYukle = useCallback(() => {
    if (!notMagaza) { setNotlar([]); return; }
    api.get(`/pdks/roster/notes?storeId=${notMagaza}`, { silent: true })
      .then((r) => setNotlar(r.data))
      .catch(() => {});
  }, [notMagaza]);
  useEffect(() => { notlariYukle(); }, [notlariYukle]);

  // Kaydedilmemis degisiklik varken sekmeyi kapatmak plani kaybettirir.
  useEffect(() => {
    if (bekleyenSayi === 0) return undefined;
    const uyar = (e) => { e.preventDefault(); e.returnValue = ''; };
    window.addEventListener('beforeunload', uyar);
    return () => window.removeEventListener('beforeunload', uyar);
  }, [bekleyenSayi]);

  // Hucre duzenlemesi icin atanabilir vardiyalar. Yalnizca duzenleme yetkisi
  // olanlar icin cekiliyor; barista bu listeyi hic istemiyor.
  useEffect(() => {
    if (!veri || !veri.can_edit || !magazaMuduru) return;
    api.get('/pdks/shifts', { silent: true })
      .then((r) => setVardiyalar(r.data.filter((v) => v.active)))
      .catch(() => {});
  }, [veri && veri.can_edit, magazaMuduru]);

  function kaydir(yon) {
    // Hafta degistirmek bekleyenleri gorunmez kilar; once sorulur.
    if (bekleyenSayi > 0 && !window.confirm(
      `${bekleyenSayi} kaydedilmemiş değişiklik var. `
      + 'Hafta değiştirirseniz kaybolur. Devam edilsin mi?',
    )) return;
    setBekleyen({});
    setCakisma(null);
    if (mod === 'hafta') {
      setAnchor(new Date(anchor.getTime() + yon * 7 * 86400000));
    } else {
      setGun(iso(new Date(new Date(`${gun}T00:00:00`).getTime() + yon * 86400000)));
    }
  }

  /// Bekleyen degisiklikleri TEK istekte kaydeder.
  ///
  /// Sunucu sozlesmesi "hepsi ya hicbiri": bir hucrede cakisma varsa hicbiri
  /// yazilmiyor ve cakismalar listeleniyor. Yonetici ya sorunlu hucreyi
  /// duzeltir ya da "yine de kaydet" der.
  async function kaydet(force = false) {
    if (bekleyenSayi === 0) return;
    setKaydediyor(true);
    setCakisma(null);
    try {
      const r = await api.put('/pdks/assignments/cells', {
        force,
        changes: Object.values(bekleyen).map((b) => ({
          user_id: b.user_id,
          work_date: b.work_date,
          shift_id: b.shift_id,
          is_day_off: b.is_day_off,
        })),
      }, { noToast: true });
      toast(`${r.data.saved} değişiklik kaydedildi`
        + (r.data.forced > 0 ? ` (${r.data.forced} tanesi çakışmaya rağmen)` : ''));
      for (const u of r.data.warnings || []) {
        toast(`${u.full_name} ${u.work_date}: ${u.label}`);
      }
      setBekleyen({});
      yukle();
    } catch (e) {
      const d = e.response && e.response.data;
      if (e.response && e.response.status === 409 && d && d.code === 'SHIFT_CONFLICT') {
        setCakisma(d);
      } else {
        toast(errorMessage(e));
      }
    } finally {
      setKaydediyor(false);
    }
  }

  /// Tek bir bekleyen degisikligi geri alir.
  function bekleyeniKaldir(anahtar) {
    setBekleyen((eski) => {
      const y = { ...eski };
      delete y[anahtar];
      return y;
    });
    setCakisma(null);
  }

  /// Haftalik plani ekiple paylas: herkese kendi haftasinin bildirimi gider.
  async function paylas() {
    if (!veri || veri.people.length === 0) { toast('Paylaşılacak plan yok'); return; }
    if (!window.confirm(
      `${fmtDate(veri.from)} – ${fmtDate(veri.to)} haftasının planı ekibe bildirilecek.\n\n`
      + 'Herkes kendi vardiyalarının özetini bildirim olarak alacak.'
    )) return;
    setPaylasiyor(true);
    try {
      const r = await api.post('/pdks/roster/publish',
        { from: veri.from, to: veri.to }, { noToast: true });
      toast(`Plan ${r.data.notified} kişiyle paylaşıldı`);
    } catch (e) {
      toast(errorMessage(e));
    } finally {
      setPaylasiyor(false);
    }
  }

  /// Haftalik plan PDF'i: ekrandaki tablonun aynisi (Personel & Rol, gun
  /// sutunlari saat + kategori, OFF / RAPOR / RT, Planli, Kadro Gucu) ve
  /// altinda plan notlari.
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

      const basliklar = [
        'Personel & Rol',
        ...veri.dates.map((d) => `${gunAdi(d)}\n${d.slice(8)}.${d.slice(5, 7)}`),
        'Planlı',
      ];
      const hucreler = veri.people.map((p) => veri.dates.map((d) => pdfHucre(p.cells[d], veri.holidays[d])));
      const satirlar = veri.people.map((p, i) => [
        `${p.user.full_name}\n${rolEtiketi(p.user.role)}`,
        ...hucreler[i].map((h) => h.metin),
        saat(p.planned_minutes),
      ]);
      const kadro = [
        'Kadro Gücü\nÇalışan sayısı',
        ...veri.dates.map((d) => `${veri.totals[d].working} Kişi\n${kadroEtiketi(veri.totals[d].working)}`),
        saat(veri.people.reduce((a, p) => a + p.planned_minutes, 0)),
      ];

      autoTable(doc, {
        head: [basliklar],
        body: [...satirlar, kadro],
        startY: 25,
        theme: 'grid',
        styles: {
          font: f, fontSize: 7, cellPadding: 2, valign: 'middle', halign: 'center',
          lineColor: [226, 232, 240], lineWidth: 0.2, textColor: [15, 23, 42],
        },
        headStyles: { font: f, fontStyle: 'bold', fontSize: 8, fillColor: [248, 250, 252], textColor: [15, 23, 42] },
        alternateRowStyles: { fillColor: [248, 250, 252] },
        columnStyles: { 0: { cellWidth: 46, halign: 'left' } },
        didParseCell: (data) => {
          if (data.section === 'head') {
            const i = data.column.index - 1;
            const d = veri.dates[i];
            if (d && veri.holidays[d]) {
              data.cell.styles.fillColor = PDF_RENK.RT.zemin;
              data.cell.styles.textColor = PDF_RENK.RT.metin;
            }
            return;
          }
          if (data.section !== 'body') return;
          const kadroSatiri = data.row.index === satirlar.length;
          if (kadroSatiri) {
            data.cell.styles.fontStyle = 'bold';
            data.cell.styles.fillColor = [226, 232, 240];
            if (data.column.index > 0) data.cell.styles.textColor = [15, 118, 110];
            return;
          }
          if (data.column.index === 0 || data.column.index === basliklar.length - 1) {
            data.cell.styles.fontStyle = 'bold';
            return;
          }
          // Ekrandaki renklendirmenin aynisi ciktida da olsun.
          const h = hucreler[data.row.index][data.column.index - 1];
          if (h && h.renk) {
            data.cell.styles.fillColor = h.renk.zemin;
            data.cell.styles.textColor = h.renk.metin;
            data.cell.styles.fontStyle = 'bold';
          }
        },
      });

      let y = doc.lastAutoTable.finalY + 8;
      if (notlar.length > 0) {
        doc.setFont(f, 'bold');
        doc.setFontSize(10);
        doc.text('Plan Notları', 14, y);
        doc.setFont(f, 'normal');
        doc.setFontSize(8);
        y += 5;
        for (const n of notlar) {
          const satir = doc.splitTextToSize(`• ${n.body}`, 268);
          if (y + satir.length * 4 > 200) { doc.addPage(); y = 16; }
          doc.text(satir, 14, y);
          y += satir.length * 4 + 1;
        }
        y += 3;
      }
      doc.setFontSize(7);
      if (y > 200) { doc.addPage(); y = 16; }
      doc.text(
        'Hafta tatili "OFF", raporlu gün "RAPOR", resmi tatil "RT" olarak işaretlenir. '
        + 'Planlı süreler NET çalışmadır: ara dinlenmesi (4857 m.68) düşülmüştür.',
        14, y,
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

      {cakisma && (
        <div className="alert warning">
          <strong>{cakisma.error}</strong>
          <ul className="cakisma-list">
            {cakisma.conflicts.map((c, i) => (
              <li key={i}>
                <strong>{c.full_name}</strong> — {fmtDate(c.work_date)}: {c.label}
                {' '}
                <button type="button" className="btn btn-sm btn-secondary"
                  onClick={() => bekleyeniKaldir(`${c.user_id}|${c.work_date}`)}>
                  bu değişikliği geri al
                </button>
              </li>
            ))}
          </ul>
          <p style={{ margin: '6px 0 0', fontSize: 'var(--fs-body)' }}>
            Yine de kaydederseniz çakışan atamalar hareket kayıtlarına
            {' '}<strong>çakışmaya rağmen atandı</strong> olarak yazılır.
          </p>
          <div className="form-actions" style={{ marginTop: 8 }}>
            <button type="button" className="btn btn-secondary" onClick={() => setCakisma(null)}>
              Kapat
            </button>
            <button type="button" className="btn btn-danger" disabled={kaydediyor}
              onClick={() => kaydet(true)}>
              Yine de kaydet
            </button>
          </div>
        </div>
      )}

      {veri && veri.people.length === 0 && (
        <div className="surface-panel"><p className="empty">Personel bulunamadı.</p></div>
      )}

      {bekleyenSayi > 0 && (
        <div className="kaydet-bar">
          <span className="kaydet-bilgi">
            <Save size={16} />
            <strong>{bekleyenSayi} değişiklik</strong> kaydedilmeyi bekliyor
          </span>
          <div className="row-actions">
            <button type="button" className="btn btn-secondary" disabled={kaydediyor}
              onClick={() => {
                if (window.confirm(`${bekleyenSayi} değişiklik geri alınacak.`)) {
                  setBekleyen({});
                  setCakisma(null);
                }
              }}>
              Vazgeç
            </button>
            <button type="button" className="btn btn-primary" disabled={kaydediyor}
              onClick={() => kaydet(false)}>
              {kaydediyor ? 'Kaydediliyor...' : 'Kaydet'}
            </button>
          </div>
        </div>
      )}

      {veri && veri.people.length > 0 && (
        mod === 'hafta'
          ? (
            <HaftaTablosu
              veri={veri}
              bekleyen={bekleyen}
              onHucre={veri.can_edit && magazaMuduru ? (kisi, gun) => setHucre({ kisi, gun }) : null}
            />
          )
          : <GunListesi veri={veri} gun={gun} />
      )}

      {veri && veri.people.length > 0 && mod === 'hafta' && (
        <NotlarKarti
          notlar={notlar}
          magazaSecili={!!notMagaza}
          duzenlenebilir={!!veri.can_edit}
          onEkle={() => setNotForm({})}
          onDuzenle={(n) => setNotForm({ not: n })}
          onSil={(n) => setNotSil(n)}
        />
      )}

      {/* Ekiple Paylas + PDF Indir (yalnizca magaza muduru). Paylasim
          KAYDETMEDEN ayri bir adim; bekleyen degisiklik varken kapali:
          paylasilan plan ekranda gorulenle ayni olmali. */}
      {veri && veri.people.length > 0 && magazaMuduru && mod === 'hafta' && (
        <div className="roster-bottom">
          <div className="roster-bottom-row">
            <button className="btn btn-primary" disabled={paylasiyor || bekleyenSayi > 0} onClick={paylas}>
              <Users size={18} /> {paylasiyor ? 'Paylaşılıyor...' : 'Ekiple Paylaş'}
            </button>
            <button className="btn btn-secondary" disabled={disa} onClick={pdfAktar}>
              <FileText size={18} /> {disa ? 'Hazırlanıyor...' : 'PDF İndir'}
            </button>
          </div>
          {bekleyenSayi > 0 && <p className="muted">Paylaşmadan önce değişiklikleri kaydedin.</p>}
        </div>
      )}

      {hucre && (
        <HucreModal
          kisi={hucre.kisi}
          gun={hucre.gun}
          mevcut={hucre.kisi.cells[hucre.gun] || []}
          bekleyen={bekleyen[`${hucre.kisi.user.id}|${hucre.gun}`] || null}
          vardiyalar={vardiyalar}
          onClose={() => setHucre(null)}
          onSec={(secim) => {
            const anahtar = `${hucre.kisi.user.id}|${hucre.gun}`;
            const mevcutHucre = hucre.kisi.cells[hucre.gun] || [];
            const tatilVar = mevcutHucre.some((c) => c.is_day_off);
            const mevcutId = mevcutHucre.find((c) => !c.is_day_off)?.shift_id ?? null;
            const suAnki = tatilVar ? 'HT' : mevcutId ? String(mevcutId) : '';
            setHucre(null);
            // Secim SUNUCUDAKI haliyle ayniysa bekleyen listesinden cikar:
            // "degistirdim sonra geri aldim" bir degisiklik degil.
            if (secim === suAnki) { bekleyeniKaldir(anahtar); return; }
            setBekleyen((eski) => ({
              ...eski,
              [anahtar]: {
                user_id: hucre.kisi.user.id,
                full_name: hucre.kisi.user.full_name,
                work_date: hucre.gun,
                is_day_off: secim === 'HT',
                shift_id: secim === 'HT' || secim === '' ? null : Number(secim),
                shift: secim === 'HT' || secim === ''
                  ? null : vardiyalar.find((v) => String(v.id) === secim) || null,
              },
            }));
            setCakisma(null);
          }}
        />
      )}

      {notForm && (
        <NotModal
          not={notForm.not}
          storeId={notMagaza}
          from={from}
          onClose={() => setNotForm(null)}
          onDone={() => { setNotForm(null); notlariYukle(); }}
        />
      )}

      {notSil && (
        <Confirm
          title="Notu Sil"
          confirmLabel="Sil"
          message={notSil.body}
          onCancel={() => setNotSil(null)}
          onConfirm={async () => {
            try {
              await api.delete(`/pdks/roster/notes/${notSil.id}`, { successMessage: 'Not silindi' });
            } catch {
              // Bildirim API katmaninda gosterilir.
            }
            setNotSil(null);
            notlariYukle();
          }}
        />
      )}
    </div>
  );
}

/// Tek hucre duzenlemesi: bir personelin bir gunu.
///
/// Sunucuya TEK istek gidiyor (PUT /pdks/assignments/cell): "bu gunu su hale
/// getir". Istemcide once silip sonra eklemek yarim kalabilirdi.
/// Tek hucre secimi.
///
/// Sunucuya GITMIYOR: secim ust bilesende birikiyor ve tek "Kaydet" ile
/// gonderiliyor. Cakisma kontrolu de kaydetme aninda sunucuda yapiliyor,
/// burada degil — kontrolu iki yerde yapmak ikisinin ayrismasi demekti.
function HucreModal({ kisi, gun, mevcut, bekleyen, vardiyalar, onClose, onSec }) {
  const tatilVar = mevcut.some((c) => c.is_day_off);
  const mevcutId = mevcut.find((c) => !c.is_day_off)?.shift_id ?? '';
  // Bekleyen bir degisiklik varsa onu gosteriyoruz; yoksa sunucudaki hali.
  const baslangic = bekleyen
    ? (bekleyen.is_day_off ? 'HT' : bekleyen.shift_id ? String(bekleyen.shift_id) : '')
    : (tatilVar ? 'HT' : mevcutId ? String(mevcutId) : '');
  const [secim, setSecim] = useState(baslangic);

  return (
    <Modal
      title={`${kisi.user.full_name} — ${fmtDate(gun)} ${gunAdi(gun, true)}`}
      onClose={onClose}
    >
      <div className="form-grid">
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
        <p className="muted" style={{ gridColumn: '1 / -1', fontSize: 'var(--fs-label)', margin: 0 }}>
          Seçim tabloya işlenir; kalıcı olması için tablonun altındaki
          {' '}<strong>Kaydet</strong> düğmesine basın.
        </p>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="button" className="btn btn-primary" onClick={() => onSec(secim)}>
            Tabloya işle
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

/// PDF hucre rengi. Ekrandaki kategori renkleriyle AYNI aile; jsPDF CSS
/// degiskeni okuyamadigi icin RGB olarak burada duruyor. Degerler acik tema
/// tonlari: cikti beyaz kagida basiliyor, koyu tema tonlari orada okunmaz.
///
/// Metin rengi de veriliyor: yalnizca zemini boyayip siyah metin birakmak
/// bazi tonlarda kucuk metin esiginin (4.5) altina duserdi.
const PDF_RENK = {
  sabah: { zemin: [219, 234, 254], metin: [30, 64, 175] },
  gunduz: { zemin: [220, 252, 231], metin: [22, 101, 52] },
  aksam: { zemin: [254, 243, 199], metin: [146, 64, 14] },
  kapanis: { zemin: [237, 233, 254], metin: [91, 33, 182] },
  // OFF / RAPOR: ekrandaki ve uygulamadaki gibi kirmizi tonlu rozet.
  OFF: { zemin: [255, 218, 214], metin: [147, 0, 10] },
  RT: { zemin: [254, 226, 226], metin: [153, 27, 27] },
};

/// Hucrenin PDF renk anahtari; pdfHucre ile AYNI onceligi izliyor ki
/// metin "RT" derken renk baska seyi anlatmasin.
function hucreRenk(hucreler, tatil) {
  if (tatil && tatil.half !== true) return PDF_RENK.RT;
  if (!hucreler || hucreler.length === 0) return null;
  if (hucreler.some((c) => c.is_day_off)) return PDF_RENK.OFF;
  const k = hucreler.find((c) => c.category)?.category;
  return PDF_RENK[k] || null;
}

function HaftaTablosu({ veri, bekleyen = {}, onHucre }) {
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
                      bekleyen={bekleyen[`${p.user.id}|${d}`] || null}
                      duzenle={onHucre ? () => onHucre(p, d) : null}
                    />
                  ))}
                  <td className="roster-total">{saat(planliSure(p, veri.dates, bekleyen))}</td>
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
    </>
  );
}

function Hucre({ hucreler: gelen, tatil, bekleyen, duzenle }) {
  const tamTatil = tatil && tatil.half !== true;
  // Bekleyen degisiklik varsa hucre ONU gosteriyor: yonetici tabloyu kurarken
  // sonucu gormeli, kaydettikten sonra degil.
  const hucreler = bekleyen
    ? (bekleyen.is_day_off
      ? [{ is_day_off: true }]
      : bekleyen.shift
        ? [{
          ...bekleyen.shift,
          is_day_off: false,
          crosses_midnight: (bekleyen.shift.end_time || '') <= (bekleyen.shift.start_time || ''),
          // Kategori ve uyarilar sunucudan gelmiyor (henuz kaydedilmedi);
          // secim ekranindaki yerel hesap kullaniliyor.
          category: null,
          warnings: [],
        }]
        : [])
    : gelen;
  const bos = !hucreler || hucreler.length === 0;
  const tatilKaydi = !bos && hucreler.some((c) => c.is_day_off);
  // Yasal uyari tasiyan hucre kirmizi cerceve aliyor; sebep title'da ve
  // kisa etiket olarak hucrede yaziyor.
  const uyarilar = bos ? [] : hucreler.flatMap((c) => c.warnings || []);

  let govde;
  if (tamTatil) {
    govde = <span className="roster-rt">RT</span>;
  } else if (tatilKaydi) {
    // Onaylanan rapor gunleri tatil satiri olarak tutulur, notu RAPOR.
    govde = <span className="roster-ht">{hucreler.some((c) => c.note === 'RAPOR') ? 'RAPOR' : 'OFF'}</span>;
  } else if (bos) {
    govde = <span className="roster-bos">{duzenle ? '+' : '-'}</span>;
  } else {
    govde = hucreler.map((c, i) => {
      const k = KATEGORI[c.category] || null;
      return (
        <span className={`roster-shift ${k ? k.sinif : ''}`} key={i}>
          <span className="roster-saat">
            {(c.start_time || '').slice(0, 5)}–{(c.end_time || '').slice(0, 5)}
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
    // Kaydedilmemis degisiklik: kesik cerceve + nokta. Renk TEK BASINA
    // yeterli degil, o yuzden hucrede nokta isareti de var.
    bekleyen ? 'bekleyen' : '',
  ].filter(Boolean).join(' ');

  // Duzenlenebilir hucre gercek bir dugme: klavyeyle de erisilebilsin.
  if (duzenle && !tamTatil) {
    return (
      <td className={sinif}>
        <button type="button" className="roster-hucre-btn" onClick={duzenle}
          title={bekleyen ? 'Kaydedilmemiş değişiklik' : baslik}>
          {govde}
          {uyarilar.length > 0 && (
            <span className="roster-uyari">{uyarilar[0].etiket}</span>
          )}
          {bekleyen && <span className="roster-bekleyen" aria-label="kaydedilmemiş">•</span>}
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
                    {c.crosses_midnight && <span className="badge warning" style={{ marginLeft: 6 }}>kapanış</span>}
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

/// Plan notlari karti: herkes okur, yonetici ekler; kayit soldan saga
/// kaydirilinca Duzenle / Sil acilir. Notlar magaza basina tutulur ve
/// haftalar arasinda gezinirken sabit kalir.
function NotlarKarti({ notlar, magazaSecili, duzenlenebilir, onEkle, onDuzenle, onSil }) {
  return (
    <section className="surface-panel roster-notes">
      <div className="roster-notes-head">
        <h3><StickyNote size={18} /> Plan Notları</h3>
        {duzenlenebilir && magazaSecili && (
          <button type="button" className="btn btn-sm btn-secondary" onClick={onEkle}>
            <Plus size={16} /> Not Ekle
          </button>
        )}
      </div>
      {!magazaSecili ? (
        <p className="muted">Notları görmek için bir mağaza seçin.</p>
      ) : notlar.length === 0 ? (
        <p className="muted">Henüz plan notu yok.</p>
      ) : (
        <div className="swipe-list">
          {notlar.map((n) => (
            <SwipeRow
              key={n.id}
              actions={duzenlenebilir ? [
                { label: 'Düzenle', icon: Pencil, tone: 'primary', onClick: () => onDuzenle(n) },
                { label: 'Sil', icon: Trash2, tone: 'danger', onClick: () => onSil(n) },
              ] : []}
            >
              <div className="card roster-note">
                <p className="roster-note-body">{n.body}</p>
                <p className="muted roster-note-meta">
                  {[fmtDateTime(n.updated_at || n.created_at), n.created_by_name || 'bilinmiyor',
                    n.updated_at ? 'düzenlendi' : null].filter(Boolean).join(' · ')}
                </p>
              </div>
            </SwipeRow>
          ))}
        </div>
      )}
    </section>
  );
}

function NotModal({ not, storeId, from, onClose, onDone }) {
  const [body, setBody] = useState(not?.body || '');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  async function submit(e) {
    e.preventDefault();
    const text = body.trim();
    if (!text) { setErr('Not boş olamaz'); return; }
    setBusy(true);
    try {
      if (not) {
        await api.put(`/pdks/roster/notes/${not.id}`, { body: text }, { noToast: true });
        toast('Not güncellendi');
      } else {
        await api.post('/pdks/roster/notes', { body: text, from, storeId }, { noToast: true });
        toast('Not eklendi');
      }
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title={not ? 'Notu Düzenle' : 'Plan Notu Ekle'} onClose={onClose} busy={busy}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Not</label>
          <textarea rows="4" maxLength={1000} value={body} onChange={(e) => setBody(e.target.value)} autoFocus />
          <p className="login-hint">Not silinene kadar her haftanın planı altında görünür ve PDF&apos;e eklenir.</p>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose} disabled={busy}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>Kaydet</button>
        </div>
      </form>
    </Modal>
  );
}

/// Rol etiketi; ekran ve PDF ortak (uygulamadaki rosterRoleLabel).
function rolEtiketi(rol) {
  const r = String(rol || '').toLowerCase();
  return {
    store_manager: 'Müdür', shift_supervisor: 'Supervisor', supervisor: 'Supervisor',
    senior_barista: 'Kıdemli Barista', barista: 'Barista', kitchen: 'Mutfak', service: 'Servis', '': 'Personel',
  }[r] || (r.charAt(0).toLocaleUpperCase('tr') + r.slice(1));
}

/// Kadro gucu etiketi (gunluk calisan sayisina gore).
function kadroEtiketi(calisan) {
  if (calisan >= 4) return 'Yeterli';
  if (calisan >= 3) return 'Min. Kadro';
  return 'Dengeli';
}

/// PDF hucresinin iki satiri ve renkleri: ekrandaki rozetin aynisi.
function pdfHucre(hucreler, tatil) {
  if (tatil && tatil.half !== true) return { metin: 'RT\nTatil', renk: PDF_RENK.RT };
  if (!hucreler || hucreler.length === 0) return { metin: '-', renk: null };
  if (hucreler.some((c) => c.is_day_off)) {
    const rapor = hucreler.some((c) => c.is_day_off && c.note === 'RAPOR');
    return { metin: rapor ? 'RAPOR\nRaporlu' : 'OFF\nHafta Tatili', renk: PDF_RENK.OFF };
  }
  const metin = hucreler.map((c) => {
    const araligi = `${(c.start_time || '').slice(0, 5)}-${(c.end_time || '').slice(0, 5)}`;
    const k = KATEGORI[c.category];
    return k ? `${araligi}\n${k.etiket}` : araligi;
  }).join('\n');
  return { metin, renk: hucreRenk(hucreler, tatil) };
}
