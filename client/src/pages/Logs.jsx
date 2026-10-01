import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ScrollText, KeyRound, Store, User, Lock, Cake, Snowflake, Hourglass,
  Refrigerator, Banknote, Trash2, ClipboardList, Undo2, Pencil, Download, Database, CalendarClock } from 'lucide-react';
import api from '../api';
import { fmtDateTime } from '../format';

// Ham islem kodlari (50+) tek dropdown'da kullanilamayacak kadar cok;
// hareket_kayitlari_denetim_gunlugu mockup'indaki gibi genis kategorilere
// gruplaniyor. Sunucu tarafinda kategori kavrami yok, tamami istemcide.
const CATEGORIES = [
  { id: 'vardiya', label: 'Vardiya & PDKS', match: (a) => a.startsWith('VARDIYA_') || a.startsWith('TALEP_') || a.startsWith('PDKS_') || a.startsWith('TATIL_') },
  { id: 'finans', label: 'Finans & Rapor', match: (a) => a.startsWith('GUNLUK_RAPOR') || a.startsWith('TRANSFER_') },
  { id: 'guvenlik', label: 'Güvenlik & Giriş', match: (a) => a === 'GIRIS' || a.startsWith('SIFRE_') || a.startsWith('KULLANICI_') || a === 'PROFIL_FOTO' },
  { id: 'skt', label: 'SKT & Zayi', match: (a) => a === 'IMHA' || a.startsWith('ZAYI_') },
  { id: 'kasa', label: 'Kasa & Petty Cash', match: (a) => a.startsWith('SATIS') || a.startsWith('PETTY_CASH') },
];
const categoryOf = (a) => CATEGORIES.find((c) => c.match(a))?.id || 'diger';

const ICON_MAP = {
  GIRIS: KeyRound, MAGAZA_OLUSTUR: Store, MAGAZA_GUNCELLE: Store, MAGAZA_SIL: Store,
  KULLANICI_OLUSTUR: User, KULLANICI_GUNCELLE: User, KULLANICI_SIL: User, SIFRE_SIFIRLA: Lock, SIFRE_DEGISTIR: Lock,
  CESIT_OLUSTUR: Cake, CESIT_GUNCELLE: Cake, CESIT_SIL: Cake,
  DONUK_EKLE: Snowflake, COZULME_BASLA: Hourglass, FOOD_DOLABI: Refrigerator, SATIS: Banknote, IMHA: Trash2,
  // Geriye donuk adet duzeltmeleri ve silmeler.
  COZULME_DUZELT: Undo2, SATIS_DUZELT: Pencil, ZAYI_DUZELT: Pencil,
  SATIS_SIL: Trash2, ZAYI_SIL: Trash2, PARTI_SIL: Trash2,
};
const icon = (a) => ICON_MAP[a] || ClipboardList;
// Silme/imha kirmizi, duzeltme sari, olusturma/giris yesil, gerisi notr.
const tone = (a) => (a.endsWith('_SIL') || a === 'IMHA' ? 'danger'
  : a.includes('DUZELT') ? 'warning'
  : (a.endsWith('_OLUSTUR') || a === 'GIRIS') ? 'success'
  : 'muted');

function csvIndir(rows) {
  const basliklar = ['Tarih', 'İşlem', 'Detay', 'Kullanıcı', 'Mağaza'];
  const kacis = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const satirlar = rows.map((l) => [
    fmtDateTime(l.created_at), l.action, l.details || '', l.username || '', l.store_name || '',
  ].map(kacis).join(','));
  const csv = '﻿' + [basliklar.join(','), ...satirlar].join('\r\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `hareket-kayitlari-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

export default function Logs() {
  const [logs, setLogs] = useState([]);
  const [category, setCategory] = useState('');

  const load = useCallback(() => {
    api.get('/logs').then((r) => setLogs(r.data)).catch(() => {});
  }, []);

  useEffect(() => { load(); }, [load]);

  const shown = category ? logs.filter((l) => categoryOf(l.action) === category) : logs;

  const counts = useMemo(() => {
    const c = { '': logs.length };
    for (const cat of CATEGORIES) c[cat.id] = logs.filter((l) => categoryOf(l.action) === cat.id).length;
    return c;
  }, [logs]);

  const today = new Date().toISOString().slice(0, 10);
  const todayCount = logs.filter((l) => (l.created_at || '').slice(0, 10) === today).length;

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><ScrollText size={20} /> Hareket Kayıtları</h2>
        <button className="btn btn-secondary" onClick={() => csvIndir(shown)} disabled={shown.length === 0}>
          <Download size={16} /> CSV
        </button>
      </div>

      <div className="grid stats" style={{ gridTemplateColumns: 'repeat(2, 1fr)' }}>
        <div className="stat stat-card">
          <span className="icon-chip primary"><Database size={16} /></span>
          <div className="label"><span>Toplam</span></div>
          <div className="value">{logs.length}</div>
          <div className="sub">sistem logu</div>
        </div>
        <div className="stat stat-card">
          <span className="icon-chip success"><CalendarClock size={16} /></span>
          <div className="label"><span>Bugün</span></div>
          <div className="value">{todayCount}</div>
          <div className="sub">işlem</div>
        </div>
      </div>

      <div className="surface-panel">
        <div className="chip-row">
          <button type="button" className={`chip ${category === '' ? 'chip-on' : ''}`} onClick={() => setCategory('')}>
            Tümü ({counts['']})
          </button>
          {CATEGORIES.map((c) => (
            <button key={c.id} type="button" className={`chip ${category === c.id ? 'chip-on' : ''}`} onClick={() => setCategory(c.id)}>
              {c.label} ({counts[c.id] || 0})
            </button>
          ))}
        </div>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Tarih</th><th>İşlem</th><th>Detay</th><th>Kullanıcı</th><th>Mağaza</th></tr>
            </thead>
            <tbody>
              {shown.length === 0 && <tr><td data-label="" colSpan="5"><p className="empty">Kayıt bulunamadı</p></td></tr>}
              {shown.map((l) => {
                const Icon = icon(l.action);
                return (
                  <tr key={l.id}>
                    <td data-label="Tarih" className="muted" style={{ fontSize: 'var(--fs-body)' }}>{fmtDateTime(l.created_at)}</td>
                    <td data-label="İşlem">
                      <span className="log-line">
                        <span className={`icon-chip ${tone(l.action)}`} style={{ width: 26, height: 26 }}><Icon size={13} /></span>
                        <span className="mono">{l.action}</span>
                      </span>
                    </td>
                    <td data-label="Detay">{l.details || '-'}</td>
                    <td data-label="Kullanıcı">{l.username || '-'}</td>
                    <td data-label="Mağaza">{l.store_name || '—'}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
