import { useCallback, useEffect, useMemo, useState } from 'react';
import { Banknote } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { fmtDateTime } from '../format';

export default function Sales() {
  const { user } = useAuth();
  const [sales, setSales] = useState([]);
  const [storeId, setStoreId] = useState('');
  const [stores, setStores] = useState([]);

  const load = useCallback(() => {
    const q = storeId ? `?storeId=${storeId}` : '';
    api.get('/sales' + q).then((r) => setSales(r.data)).catch(() => {});
  }, [storeId]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    if (user.role === 'super_admin') api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [user.role]);

  const total = useMemo(() => sales.reduce((s, x) => s + x.quantity, 0), [sales]);
  const revenue = useMemo(
    () => sales.reduce((s, x) => s + (x.unit_price ? x.quantity * x.unit_price : 0), 0),
    [sales]
  );

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Banknote size={20} /> Satış Geçmişi</h2>
        {user.role === 'super_admin' && (
          <select value={storeId} onChange={(e) => setStoreId(e.target.value)}>
            <option value="">Tüm Mağazalar</option>
            {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        )}
      </div>

      <div className="surface-panel">
        <div className="grid stats">
          <div className="stat stat-card">
            <div className="label"><span>Toplam Satış Adedi</span></div>
            <div className="value">{total}</div>
            <div className="sub">son {sales.length} işlem</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span>Toplam Ciro</span></div>
            <div className="value">{revenue.toLocaleString('tr-TR')} TL</div>
            <div className="sub">fiyat girilen satışlar</div>
          </div>
        </div>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Ürün</th><th>Adet</th><th>Birim Fiyat</th><th>Tutar</th><th>Satış Yapan</th><th>Tarih</th></tr>
            </thead>
            <tbody>
              {sales.length === 0 && <tr><td data-label="" colSpan="7"><p className="empty">Satış kaydı bulunamadı</p></td></tr>}
              {sales.map((s) => (
                <tr key={s.id}>
                  <td data-label="Ürün"><strong>{s.product_name}</strong></td>
                  <td data-label="Adet">{s.quantity}</td>
                  <td data-label="Birim Fiyat">{s.unit_price ? `${s.unit_price.toLocaleString('tr-TR')} TL` : '-'}</td>
                  <td data-label="Tutar">{s.unit_price ? `${(s.quantity * s.unit_price).toLocaleString('tr-TR')} TL` : '-'}</td>
                  <td data-label="Satış Yapan">{s.sold_by_name || '-'}</td>
                  <td data-label="Tarih" className="muted" style={{ fontSize: 13 }}>{fmtDateTime(s.sold_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
