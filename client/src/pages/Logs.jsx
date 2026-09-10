import { useCallback, useEffect, useState } from 'react';
import {
  ScrollText, KeyRound, Store, User, Lock, Cake, Snowflake, Hourglass,
  Refrigerator, Banknote, Trash2, ClipboardList,
} from 'lucide-react';
import api from '../api';
import { fmtDateTime } from '../format';

export default function Logs() {
  const [logs, setLogs] = useState([]);
  const [filter, setFilter] = useState('');

  const load = useCallback(() => {
    api.get('/logs').then((r) => setLogs(r.data)).catch(() => {});
  }, []);

  useEffect(() => { load(); }, [load]);

  const shown = filter ? logs.filter((l) => l.action === filter) : logs;

  const actions = [...new Set(logs.map((l) => l.action))];

  const icon = (a) => {
    const map = {
      GIRIS: KeyRound, MAGAZA_OLUSTUR: Store, MAGAZA_GUNCELLE: Store, MAGAZA_SIL: Store,
      KULLANICI_OLUSTUR: User, KULLANICI_GUNCELLE: User, KULLANICI_SIL: User, SIFRE_SIFIRLA: Lock, SIFRE_DEGISTIR: Lock,
      CESIT_OLUSTUR: Cake, CESIT_GUNCELLE: Cake, CESIT_SIL: Cake,
      DONUK_EKLE: Snowflake, COZULME_BASLA: Hourglass, FOOD_DOLABI: Refrigerator, SATIS: Banknote, IMHA: Trash2,
    };
    return map[a] || ClipboardList;
  };

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><ScrollText size={20} /> Hareket Kayıtları</h2>
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="">Tüm İşlemler</option>
          {actions.map((a) => <option key={a} value={a}>{a}</option>)}
        </select>
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
                    <td data-label="Tarih" className="muted" style={{ fontSize: 13 }}>{fmtDateTime(l.created_at)}</td>
                    <td data-label="İşlem"><span className="mono log-line"><Icon size={13} /> {l.action}</span></td>
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
