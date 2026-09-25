import { useCallback, useEffect, useState } from 'react';
import { BarChart3, FileSpreadsheet, FileText, RefreshCw } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, toast } from '../components/ui';
import { fmtDate, fmtMoney, errorMessage } from '../format';

const ENTRY_ROLES = ['store_manager', 'shift_supervisor'];

// Bu alanlar sistemdeki pasta satis ve imha kayitlarindan otomatik dolar.
const SYSTEM_FIELDS = ['food_usd', 'food_usd_try', 'food_mo_try'];

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
    ...fields.derived.map((f) => f.label),
  ];
  const rows = page.items.map((item) => [
    fmtDate(item.report_date),
    ...(showStore ? [item.store_name || '-'] : []),
    ...fields.entry.map((f) => formatValue(item[f.key], f.type)),
    ...fields.derived.map((f) => formatValue(item.metrics[f.key], f.type)),
  ]);
  const summary = [
    `TOPLAM (${page.summary.days} gün)`,
    ...(showStore ? [''] : []),
    ...fields.entry.map((f) => formatValue(page.summary.totals[f.key], f.type)),
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
  const [fields, setFields] = useState({ entry: [], derived: [] });
  const [period, setPeriod] = useState('week');
  const [showAdd, setShowAdd] = useState(false);
  const [detail, setDetail] = useState(null);
  const [reload, setReload] = useState(0);
  const [exporting, setExporting] = useState(false);

  const canEnter = ENTRY_ROLES.includes(user.role);
  const showStore = !user.store_id;

  const load = useCallback(() => {
    api.get(`/daily-reports?period=${period}`)
      .then((r) => setPage(r.data))
      .catch(() => {});
  }, [period]);

  useEffect(() => { load(); }, [load, reload]);
  useEffect(() => {
    api.get('/daily-reports/fields', { silent: true })
      .then((r) => setFields(r.data))
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
        {canEnter && (
          <button className="btn btn-primary" onClick={() => setShowAdd(true)}>+ Gün Ekle</button>
        )}
      </div>

      <div className="surface-panel">
        <div className="chip-row" style={{ marginBottom: 12 }}>
          <button type="button" className={`chip ${period === 'week' ? 'chip-on' : ''}`} onClick={() => setPeriod('week')}>Haftalık</button>
          <button type="button" className={`chip ${period === 'month' ? 'chip-on' : ''}`} onClick={() => setPeriod('month')}>Aylık</button>
        </div>
        {page && (
          <p className="muted" style={{ fontSize: 13, margin: '0 0 12px' }}>
            {fmtDate(page.from)} – {fmtDate(page.to)} · {summary.days} gün
          </p>
        )}
        <div className="actions">
          <button className="btn btn-secondary" onClick={exportExcel} disabled={exporting}>
            <FileSpreadsheet size={16} /> Excel
          </button>
          <button className="btn btn-secondary" onClick={exportPdf} disabled={exporting}>
            <FileText size={16} /> PDF
          </button>
        </div>
      </div>

      {summary && summary.days > 0 && (
        <div className="surface-panel">
          <h3 style={{ margin: '0 0 4px' }}>Dönem Özeti</h3>
          <p className="muted" style={{ fontSize: 12, margin: '0 0 12px' }}>
            Oranlar günlerin ortalaması değil, toplam veriden hesaplanır.
          </p>
          <div className="report-grid">
            {fields.entry.map((f) => (
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

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr>
                <th>Tarih</th>
                {showStore && <th>Mağaza</th>}
                <th>NET SALES</th><th>ADT</th><th>AT</th><th>IPT</th>
                <th>FOOD MARKOUT %</th><th>APP%</th><th>Detay</th>
              </tr>
            </thead>
            <tbody>
              {(!page || page.items.length === 0) && (
                <tr><td data-label="" colSpan="9"><p className="empty">Bu dönemde rapor kaydı yok.</p></td></tr>
              )}
              {page && page.items.map((item) => (
                <tr key={item.id}>
                  <td data-label="Tarih"><strong>{fmtDate(item.report_date)}</strong></td>
                  {showStore && <td data-label="Mağaza">{item.store_name}</td>}
                  <td data-label="NET SALES">{formatValue(item.net_sales, 'money')}</td>
                  <td data-label="ADT">{formatValue(item.adt, 'int')}</td>
                  <td data-label="AT">{formatValue(item.metrics.at, 'money')}</td>
                  <td data-label="IPT">{formatValue(item.metrics.ipt, 'number')}</td>
                  <td data-label="FOOD MARKOUT %">{formatValue(item.metrics.food_markout_pct, 'percent')}</td>
                  <td data-label="APP%">{formatValue(item.metrics.app_pct, 'percent')}</td>
                  <td data-label="Detay">
                    <button className="btn btn-sm btn-secondary" onClick={() => setDetail(item)}>Detay</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {showAdd && (
        <EntryModal
          fields={fields}
          onClose={() => setShowAdd(false)}
          onDone={() => { setShowAdd(false); setReload((n) => n + 1); }}
        />
      )}

      {detail && (
        <Modal title={fmtDate(detail.report_date)} onClose={() => setDetail(null)}>
          <div className="report-grid">
            {fields.entry.map((f) => (
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

function EntryModal({ fields, onClose, onDone }) {
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [values, setValues] = useState({});
  const [system, setSystem] = useState({});
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  // Food alanlari sistemdeki satis/imha kayitlarindan dolar. Güne ait kayit
  // varsa onceki degerler kullanilir; kullanici duzeltmisse kaybolmasin.
  useEffect(() => {
    if (!date) return;
    api.get(`/daily-reports/day/${date}`, { silent: true })
      .then((r) => {
        const saved = r.data && r.data.report;
        const suggested = (r.data && r.data.suggested) || {};
        setSystem(suggested);
        setValues(Object.fromEntries(fields.entry.map((f) => {
          if (saved && saved[f.key] !== undefined && saved[f.key] !== null) {
            return [f.key, String(saved[f.key])];
          }
          if (SYSTEM_FIELDS.includes(f.key)) return [f.key, String(suggested[f.key] ?? '')];
          return [f.key, ''];
        })));
      })
      .catch(() => { setValues({}); setSystem({}); });
  }, [date, fields]);

  async function submit(e) {
    e.preventDefault();
    setErr('');
    const payload = { report_date: date };
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
      await api.post('/daily-reports', payload, { noToast: true, busyMessage: 'Rapor kaydediliyor...' });
      toast('Rapor kaydedildi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Günlük Rapor" onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Tarih</label>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            Aynı gün için tekrar giriş mevcut kaydı günceller.
          </p>
        </div>
        {fields.entry.map((f) => {
          const fromSystem = SYSTEM_FIELDS.includes(f.key);
          return (
            <div className="field" key={f.key}>
              <label>{f.label}</label>
              <div className="system-field">
                <input
                  value={values[f.key] ?? ''}
                  onChange={(e) => setValues((v) => ({ ...v, [f.key]: e.target.value }))}
                  inputMode="decimal"
                  required
                />
                {fromSystem && (
                  <button
                    type="button"
                    className="btn btn-sm btn-secondary"
                    title="Sistemden doldur"
                    onClick={() => setValues((v) => ({ ...v, [f.key]: String(system[f.key] ?? 0) }))}
                  >
                    <RefreshCw size={14} />
                  </button>
                )}
              </div>
              {fromSystem && (
                <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
                  Sistemdeki satış ve imha kayıtlarından: {formatValue(system[f.key], f.type)}
                </p>
              )}
            </div>
          );
        })}
        <p className="muted" style={{ fontSize: 12 }}>
          FOOD alanları sistemdeki pasta satış ve imha kayıtlarından otomatik dolar;
          gerekirse değiştirebilirsiniz. AT, IPT, FOOD MARKOUT %, FOOD UPH,
          MODIFIERS % ve APP% girilen değerlerden otomatik hesaplanır.
        </p>
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
