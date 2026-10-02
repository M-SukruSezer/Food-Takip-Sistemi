import { useCallback, useEffect, useState } from 'react';
import { ClipboardCheck, Plus } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { TalepModal, TalepListesi, karsiTarafBekliyor } from '../components/pdks/Talepler';
import { errorMessage } from '../format';

// Taleplerim (yalnizca barista): izin, vardiya takasi, haftalik OFF ve rapor
// taleplerinin olusturuldugu ve durumlarinin izlendigi modul. Takasta karsi
// taraf olan partner onayini da buradan verir.
export default function Requests() {
  const { user } = useAuth();
  const [talepler, setTalepler] = useState(null);
  const [bakiye, setBakiye] = useState(null);
  const [hata, setHata] = useState('');
  const [filtre, setFiltre] = useState('ALL');
  const [form, setForm] = useState(false);
  const [reload, setReload] = useState(0);

  const yukle = useCallback(() => {
    api.get('/pdks/requests')
      .then((r) => { setTalepler(r.data); setHata(''); })
      .catch((e) => setHata(errorMessage(e)));
    api.get('/pdks/requests/balances', { silent: true }).then((r) => setBakiye(r.data)).catch(() => {});
  }, []);
  useEffect(() => { yukle(); }, [yukle, reload]);

  const liste = talepler || [];
  const gorunen = filtre === 'PENDING' ? liste.filter((r) => r.status === 'PENDING')
    : filtre === 'DONE' ? liste.filter((r) => r.status !== 'PENDING')
    : liste;
  const bekleyen = liste.filter((r) => r.status === 'PENDING').length;
  const onayimda = liste.filter((r) => karsiTarafBekliyor(r)
    && Number(r.target_user_id) === Number(user.id)).length;

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><ClipboardCheck size={20} /> Taleplerim</h2>
        <div className="actions">
          <button className="btn btn-primary" onClick={() => setForm(true)}>
            <Plus size={16} /> Yeni Talep
          </button>
        </div>
      </div>

      {hata && <div className="alert error">{hata}</div>}

      <div className="grid stats">
        <div className="stat stat-card"><div className="label">Bekleyen</div><div className="value">{bekleyen}</div></div>
        <div className="stat stat-card">
          <div className="label">Kalan İzin</div>
          <div className="value">{bakiye ? `${bakiye.leave.remaining_days} gün` : '—'}</div>
        </div>
        <div className="stat stat-card"><div className="label">Onayımı Bekleyen</div><div className="value">{onayimda}</div></div>
      </div>

      <section className="surface-panel">
        <div className="chip-row" style={{ marginBottom: 10 }}>
          {[['ALL', 'Tümü'], ['PENDING', 'Bekleyen'], ['DONE', 'Sonuçlanan']].map(([v, l]) => (
            <button key={v} type="button" className={`chip ${filtre === v ? 'chip-on' : ''}`}
              onClick={() => setFiltre(v)}>{l}</button>
          ))}
        </div>
        {talepler && (
          <TalepListesi talepler={gorunen} user={user} onChange={() => setReload((n) => n + 1)} />
        )}
      </section>

      {form && (
        <TalepModal
          bakiye={bakiye}
          onClose={() => setForm(false)}
          onDone={() => { setForm(false); setReload((n) => n + 1); }}
        />
      )}
    </div>
  );
}
