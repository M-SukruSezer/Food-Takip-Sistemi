import { useCallback, useEffect, useState } from 'react';
import { BarChart3, FileSpreadsheet, FileText, FolderUp, Pencil, Plus, Sparkles, Trash2 } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, Confirm, toast } from '../components/ui';
import { ExpandableFab, SwipeRow } from '../components/actions';
import { fmtDate, fmtMoney, errorMessage } from '../format';

const ENTRY_ROLES = ['store_manager', 'shift_supervisor'];


// Degerleri turune gore bicimler. Paydasi sifir olan oran sunucudan null
// gelir; ekranda "-" gosterilir.
function formatValue(value, type) {
  if (value === null || value === undefined) return '-';
  if (type === 'money') return fmtMoney(value);
  if (type === 'percent') return `${(Number(value) * 100).toFixed(2)}%`;
  if (type === 'int') return Number(value).toLocaleString('tr-TR');
  return Number(value).toFixed(2);
}

// Tablo iskeleti Excel ve PDF icin tek yerden uretilir; iki cikti sapmaz.
function buildTable(page, fields, showStore) {
  const headers = [
    'Tarih',
    ...(showStore ? ['Mağaza'] : []),
    ...fields.entry.map((f) => f.label),
    ...fields.system.map((f) => f.label),
    ...fields.derived.map((f) => f.label),
  ];
  const rows = page.items.map((item) => [
    fmtDate(item.report_date),
    ...(showStore ? [item.store_name || '-'] : []),
    ...fields.entry.map((f) => formatValue(item[f.key], f.type)),
    ...fields.system.map((f) => formatValue(item[f.key], f.type)),
    ...fields.derived.map((f) => formatValue(item.metrics[f.key], f.type)),
  ]);
  const summary = [
    `TOPLAM (${page.summary.days} gün)`,
    ...(showStore ? [''] : []),
    ...fields.entry.map((f) => formatValue(page.summary.totals[f.key], f.type)),
    ...fields.system.map((f) => formatValue(page.summary.totals[f.key], f.type)),
    ...fields.derived.map((f) => formatValue(page.summary.metrics[f.key], f.type)),
  ];
  return { headers, rows, summary };
}

function fileName(page, ext) {
  const label = page.period === 'month' ? 'aylik' : 'haftalik';
  return `operasyon-raporu-${label}-${page.from}_${page.to}.${ext}`;
}

export default function DailyReport() {
  const { user } = useAuth();
  const [page, setPage] = useState(null);
  const [fields, setFields] = useState({ entry: [], system: [], derived: [] });
  const [period, setPeriod] = useState('week');
  const [searchParams, setSearchParams] = useSearchParams();
  const [showAdd, setShowAdd] = useState(false);
  const [detail, setDetail] = useState(null);
  const [editing, setEditing] = useState(null);
  const [reload, setReload] = useState(0);
  const [exporting, setExporting] = useState(false);
  const [showExport, setShowExport] = useState(false);
  const [removing, setRemoving] = useState(null);

  const canEnter = ENTRY_ROLES.includes(user.role);
  const showStore = !user.store_id;

  const load = useCallback(() => {
    api.get(`/daily-reports?period=${period}`)
      .then((r) => setPage(r.data))
      .catch(() => {});
  }, [period]);

  // Kisayol dugmesinden ?new=1 ile gelindiginde form kendiliginden acilir.
  // Parametre hemen temizlenir, yoksa yenilemede form tekrar aciliyor.
  useEffect(() => {
    if (searchParams.get('new') !== '1') return;
    setShowAdd(true);
    const next = new URLSearchParams(searchParams);
    next.delete('new');
    setSearchParams(next, { replace: true });
  }, [searchParams, setSearchParams]);

  useEffect(() => { load(); }, [load, reload]);
  useEffect(() => {
    api.get('/daily-reports/fields', { silent: true })
      .then((r) => setFields({ entry: [], system: [], derived: [], ...r.data }))
      .catch(() => {});
  }, []);

  // Dosya kutuphaneleri yalnizca disa aktarirken indirilir; paket boyutu
  // normal kullanimda buyumesin.
  async function exportExcel() {
    if (!page || page.items.length === 0) { toast('Dışa aktarılacak kayıt yok'); return; }
    setExporting(true);
    try {
      const XLSX = await import('xlsx');
      const { headers, rows, summary } = buildTable(page, fields, showStore);
      const sheet = XLSX.utils.aoa_to_sheet([headers, ...rows, summary]);
      const book = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(book, sheet, 'Operasyon Raporu');
      XLSX.writeFile(book, fileName(page, 'xlsx'));
    } catch (e) {
      toast('Dışa aktarılamadı');
    } finally {
      setExporting(false);
    }
  }

  async function exportPdf() {
    if (!page || page.items.length === 0) { toast('Dışa aktarılacak kayıt yok'); return; }
    setExporting(true);
    try {
      const { jsPDF } = await import('jspdf');
      const { default: autoTable } = await import('jspdf-autotable');
      const { headers, rows, summary } = buildTable(page, fields, showStore);
      // 15 kolon dikey sayfaya sigmiyor.
      const doc = new jsPDF({ orientation: 'landscape' });
      doc.setFontSize(14);
      doc.text(period === 'month' ? 'Aylık Operasyon Raporu' : 'Haftalık Operasyon Raporu', 14, 14);
      doc.setFontSize(9);
      doc.text(`${fmtDate(page.from)} – ${fmtDate(page.to)}`, 14, 20);
      autoTable(doc, {
        head: [headers],
        body: [...rows, summary],
        startY: 25,
        styles: { fontSize: 6 },
        headStyles: { fontSize: 6, fillColor: [220, 220, 220], textColor: 20 },
      });
      doc.save(fileName(page, 'pdf'));
    } catch (e) {
      toast('Dışa aktarılamadı');
    } finally {
      setExporting(false);
    }
  }

  const summary = page && page.summary;

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><BarChart3 size={20} /> Rapor Paneli</h2>
      </div>

      <div className="surface-panel">
        <div className="chip-row" style={{ marginBottom: 12 }}>
          <button type="button" className={`chip ${period === 'week' ? 'chip-on' : ''}`} onClick={() => setPeriod('week')}>Haftalık</button>
          <button type="button" className={`chip ${period === 'month' ? 'chip-on' : ''}`} onClick={() => setPeriod('month')}>Aylık</button>
        </div>
        {page && (
          <p className="muted" style={{ fontSize: 'var(--fs-body)', margin: 0 }}>
            {fmtDate(page.from)} – {fmtDate(page.to)} · {summary.days} gün
          </p>
        )}
      </div>

      {summary && summary.days > 0 && (
        <div className="surface-panel">
          <h3 style={{ margin: '0 0 4px' }}>Dönem Özeti</h3>
          <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '0 0 12px' }}>
            Oranlar günlerin ortalaması değil, toplam veriden hesaplanır.
          </p>
          <div className="report-grid">
            {[...fields.entry, ...fields.system].map((f) => (
              <div className="report-cell" key={f.key}>
                <span>{f.label}</span>
                <strong>{formatValue(summary.totals[f.key], f.type)}</strong>
              </div>
            ))}
            {fields.derived.map((f) => (
              <div className="report-cell derived" key={f.key}>
                <span>{f.label}</span>
                <strong>{formatValue(summary.metrics[f.key], f.type)}</strong>
              </div>
            ))}
          </div>
        </div>
      )}

      {(!page || page.items.length === 0) ? (
        <div className="card"><p className="empty">Bu dönemde rapor kaydı yok.</p></div>
      ) : (
        <div className="swipe-list">
          {page.items.map((item) => (
            <SwipeRow
              key={item.id}
              actions={canEnter ? [
                { label: 'Düzenle', icon: Pencil, tone: 'primary', onClick: () => setEditing(item) },
                { label: 'Sil', icon: Trash2, tone: 'danger', onClick: () => setRemoving(item) },
              ] : []}
            >
              <article className="card report-item">
                <div className="report-item-head">
                  <strong>{fmtDate(item.report_date)}</strong>
                  <span className="report-item-sales">{formatValue(item.net_sales, 'money')}</span>
                </div>
                {showStore && item.store_name && <p className="muted report-item-store">{item.store_name}</p>}
                <div className="report-metrics">
                  <span>AT <strong>{formatValue(item.metrics.at, 'money')}</strong></span>
                  <span>IPT <strong>{formatValue(item.metrics.ipt, 'number')}</strong></span>
                  <span>FOOD MARKOUT <strong>{formatValue(item.metrics.food_markout_pct, 'percent')}</strong></span>
                  <span>APP <strong>{formatValue(item.metrics.app_pct, 'percent')}</strong></span>
                </div>
                <div className="report-item-foot">
                  <span className="muted">
                    {formatValue(item.adt, 'int')} fiş · {formatValue(item.product_qty, 'int')} ürün · {item.created_by_name || 'bilinmiyor'}
                  </span>
                  <button type="button" className="btn btn-sm btn-secondary" onClick={() => setDetail(item)}>Detay</button>
                </div>
              </article>
            </SwipeRow>
          ))}
        </div>
      )}

      {/* Gun Ekle ve Disa Aktar tek yuzen dugmede: dokununca acilir. */}
      <ExpandableFab
        actions={[
          { label: 'Dışa Aktar', icon: FolderUp, onClick: () => setShowExport(true) },
          ...(canEnter ? [{ label: 'Gün Ekle', icon: Plus, onClick: () => setShowAdd(true) }] : []),
        ]}
      />

      {showExport && (
        <ExportModal
          page={page}
          storeLabel={user.store_name || 'Tüm Şubeler'}
          busy={exporting}
          onClose={() => setShowExport(false)}
          onExport={async (pdf) => {
            await (pdf ? exportPdf() : exportExcel());
            setShowExport(false);
          }}
        />
      )}

      {removing && (
        <Confirm
          title="Raporu Sil"
          confirmLabel="Sil"
          message={`${fmtDate(removing.report_date)} — ${fmtMoney(removing.net_sales)}. Bu günün raporu silinecek.`}
          onCancel={() => setRemoving(null)}
          onConfirm={async () => {
            try {
              await api.delete(`/daily-reports/${removing.id}`, { successMessage: 'Rapor silindi' });
            } catch {
              // Bildirim api katmanindan gelir.
            }
            setRemoving(null);
            setReload((n) => n + 1);
          }}
        />
      )}

      {showAdd && (
        <EntryModal
          fields={fields}
          onClose={() => setShowAdd(false)}
          onDone={() => { setShowAdd(false); setReload((n) => n + 1); }}
        />
      )}

      {editing && (
        <EntryModal
          fields={fields}
          existing={editing}
          onClose={() => setEditing(null)}
          onDone={() => { setEditing(null); setReload((n) => n + 1); }}
        />
      )}

      {detail && (
        <Modal title={fmtDate(detail.report_date)} onClose={() => setDetail(null)}>
          <div className="report-grid">
            {[...fields.entry, ...fields.system].map((f) => (
              <div className="report-cell" key={f.key}>
                <span>{f.label}</span><strong>{formatValue(detail[f.key], f.type)}</strong>
              </div>
            ))}
            {fields.derived.map((f) => (
              <div className="report-cell derived" key={f.key}>
                <span>{f.label}</span>
                <strong>{formatValue(detail.metrics[f.key], f.type)}</strong>
                {f.formula && <em>{f.formula}</em>}
              </div>
            ))}
          </div>
        </Modal>
      )}
    </div>
  );
}

/// Gunluk veri girisi ve duzenlemesi.
///
/// Formda yalnizca elle girilen alanlar var. Food alanlari sistemdeki pasta
/// satis ve zayi kayitlarindan hesaplandigi icin girilmez; okunur gosterilir.
///
/// `existing` verilirse kayitli gun duzenlenir ve tarih degistirilemez —
/// tarihi degistirmek ayni gune ikinci kayit cakismasi olusturuyor.
function EntryModal({ fields, existing, onClose, onDone }) {
  const editing = !!existing;
  const [date, setDate] = useState(
    () => (existing ? existing.report_date : new Date().toISOString().slice(0, 10))
  );
  const [values, setValues] = useState(() =>
    existing
      ? Object.fromEntries(fields.entry.map((f) => [f.key, String(existing[f.key] ?? '')]))
      : {}
  );
  const [system, setSystem] = useState({});
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  // Sistemin o gun icin hesapladigi food rakamlari ve (yeni girişte) kayitli
  // degerler yuklenir. Duzenlemede alanlar zaten dolu; ustune yazilmaz.
  useEffect(() => {
    if (!date) return;
    api.get(`/daily-reports/day/${date}`, { silent: true })
      .then((r) => {
        setSystem((r.data && r.data.suggested) || {});
        if (editing) return;
        const saved = r.data && r.data.report;
        setValues(Object.fromEntries(fields.entry.map((f) => [
          f.key,
          saved && saved[f.key] !== undefined && saved[f.key] !== null ? String(saved[f.key]) : '',
        ])));
      })
      .catch(() => { setSystem({}); });
  }, [date, fields, editing]);

  async function submit(e) {
    e.preventDefault();
    setErr('');
    const payload = editing ? {} : { report_date: date };
    for (const f of fields.entry) {
      const raw = String(values[f.key] ?? '').replace(',', '.').trim();
      if (raw === '') { setErr(`${f.label} zorunludur`); return; }
      const n = Number(raw);
      if (!Number.isFinite(n) || n < 0) { setErr(`${f.label} 0 veya daha büyük bir sayı olmalıdır`); return; }
      if (f.type === 'int' && !Number.isInteger(n)) { setErr(`${f.label} tam sayı olmalıdır`); return; }
      payload[f.key] = n;
    }
    setBusy(true);
    try {
      if (editing) {
        await api.put(`/daily-reports/${existing.id}`, payload,
          { noToast: true, busyMessage: 'Rapor güncelleniyor...' });
        toast('Rapor güncellendi');
      } else {
        await api.post('/daily-reports', payload,
          { noToast: true, busyMessage: 'Rapor kaydediliyor...' });
        toast('Rapor kaydedildi');
      }
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title={editing ? 'Günlük Raporu Düzenle' : 'Günlük Rapor'} onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Tarih</label>
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            disabled={editing}
            required
          />
          <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '4px 0 0' }}>
            {editing
              ? 'Tarih değiştirilemez. Farklı bir gün için kaydı silip yeniden girin.'
              : 'Aynı gün için tekrar giriş mevcut kaydı günceller.'}
          </p>
        </div>
        {fields.entry.map((f) => (
          <div className="field" key={f.key}>
            <label>{f.label}</label>
            <input
              value={values[f.key] ?? ''}
              onChange={(e) => setValues((v) => ({ ...v, [f.key]: e.target.value }))}
              inputMode="decimal"
              required
            />
          </div>
        ))}
        {fields.system.length > 0 && (
          <div className="system-box">
            <p className="system-box-title"><Sparkles size={14} /> Sistemden gelen değerler</p>
            {fields.system.map((f) => (
              <div className="system-box-row" key={f.key}>
                <span>{f.label}</span>
                <strong>{formatValue(system[f.key], f.type)}</strong>
              </div>
            ))}
          </div>
        )}
        <p className="muted" style={{ fontSize: 'var(--fs-label)' }}>
          FOOD alanları o günün pasta satış ve zayi kayıtlarından hesaplanır, elle
          girilmez. AT, IPT, FOOD MARKOUT %, FOOD UPH, MODIFIERS % ve APP% girilen
          değerlerden otomatik hesaplanır.
        </p>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? (editing ? 'Güncelleniyor...' : 'Kaydediliyor...') : (editing ? 'Güncelle' : 'Kaydet')}
          </button>
        </div>
      </form>
    </Modal>
  );
}

/**
 * Raporu disa aktar (standart form): dosya bicimi secilir, kapsam bilgi
 * olarak gosterilir.
 */
function ExportModal({ page, storeLabel, busy, onClose, onExport }) {
  const [pdf, setPdf] = useState(false);
  return (
    <Modal title="Raporu Dışa Aktar" onClose={onClose} busy={busy}>
      <form onSubmit={(e) => { e.preventDefault(); onExport(pdf); }}>
        <div className="field">
          <label>Dosya biçimi</label>
          <div className="export-choices">
            <button type="button" className={`export-choice${!pdf ? ' on' : ''}`} aria-pressed={!pdf} onClick={() => setPdf(false)}>
              <FileSpreadsheet size={22} />
              <strong>Excel</strong>
              <span>.xlsx tablo</span>
            </button>
            <button type="button" className={`export-choice${pdf ? ' on' : ''}`} aria-pressed={pdf} onClick={() => setPdf(true)}>
              <FileText size={22} />
              <strong>PDF</strong>
              <span>.pdf A4 döküm</span>
            </button>
          </div>
        </div>
        <div className="field">
          <label>Kapsam</label>
          <div className="export-scope">
            <span>Mağaza <strong>{storeLabel}</strong></span>
            <span>Tarih aralığı <strong>{page ? `${fmtDate(page.from)} — ${fmtDate(page.to)} (${page.items.length} kayıt)` : '-'}</strong></span>
          </div>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose} disabled={busy}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>{busy ? 'Hazırlanıyor...' : 'Dışa Aktar'}</button>
        </div>
      </form>
    </Modal>
  );
}
