import { useEffect, useState } from 'react';
import { Store, ChevronRight, ArrowLeft } from 'lucide-react';
import api from '../api';
import { errorMessage } from '../format';
import { Puantaj } from './PdksAdmin';

/// IK ekrani: magaza listesi -> secilen magazanin personel puantaji.
///
/// Neden Devam Yonetimi'nden ayri bir sayfa: IK rolu yalnizca /stores ve
/// /pdks/timesheet uclarina erisiyor. Devam Yonetimi acilirken anlik durum,
/// vardiya ve talep uclarini da cagiriyor; IK'da hepsi 403 doner ve sayfa
/// hata yiginiyla acilirdi. Bu sayfa yalnizca izin verilen iki ucu kullaniyor
/// ve puantaj tablosunu Devam Yonetimi ile PAYLASIYOR.
export default function Timesheet() {
  const [magazalar, setMagazalar] = useState(null);
  const [secili, setSecili] = useState(null);
  const [hata, setHata] = useState('');

  useEffect(() => {
    api.get('/stores')
      .then((r) => {
        const aktif = r.data.filter((m) => m.active);
        setMagazalar(aktif);
        // Tek magazaya atanmis IK kullanicisinda araya liste koymak gereksiz
        // bir dokunus; dogrudan puantaja gidiliyor.
        if (aktif.length === 1) setSecili(aktif[0]);
      })
      .catch((e) => { setMagazalar([]); setHata(errorMessage(e)); });
  }, []);

  if (magazalar === null) return null;

  if (!secili) {
    return (
      <div className="page-shell">
        <div className="surface-panel">
          <h2 style={{ margin: 0, fontSize: 18 }}>Puantaj</h2>
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            Puantajını görmek istediğiniz mağazayı seçin.
          </p>
        </div>
        {hata && <div className="alert error">{hata}</div>}
        {magazalar.length === 0 && !hata && (
          <div className="surface-panel">
            <p className="empty">Size mağaza atanmamış. Yöneticinizle görüşün.</p>
          </div>
        )}
        <div className="grid">
          {magazalar.map((m) => (
            <button
              type="button"
              key={m.id}
              className="card store-pick"
              onClick={() => setSecili(m)}
            >
              <span className="store-pick-ico"><Store size={22} /></span>
              <span className="store-pick-text">
                <strong>{m.name}</strong>
                <span className="muted">{m.user_count ?? 0} personel</span>
              </span>
              <ChevronRight size={18} className="store-pick-arrow" />
            </button>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="page-shell">
      <div className="surface-panel mo-head">
        {/* Tek magazaya atanmis kullanicida geri donecek liste yok. */}
        {magazalar.length > 1 && (
          <button className="btn btn-sm btn-secondary" onClick={() => setSecili(null)}>
            <ArrowLeft size={16} /> Mağazalar
          </button>
        )}
        <h2 style={{ margin: 0, fontSize: 17 }}>{secili.name} — Puantaj</h2>
      </div>
      <Puantaj storeId={secili.id} />
    </div>
  );
}
