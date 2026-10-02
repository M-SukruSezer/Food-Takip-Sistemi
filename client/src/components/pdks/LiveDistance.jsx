import { useEffect, useState } from 'react';
import { LocateFixed, LocateOff, Locate } from 'lucide-react';

// Magazaya CANLI uzaklik (uygulamadaki LiveStoreDistance'in web karsiligi).
//
// KVKK: konum yalnizca bu bilesen ekrandayken tarayicida kullanilir, sunucuya
// gonderilmez. Giris-cikis dogrulamasi yine okutma anindaki konumla sunucuda
// yapilir; burada gosterilen yalnizca bilgi.

/** Iki koordinat arasi metre (haversine). */
export function distanceMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

export function formatDistance(m) {
  return m < 1000 ? `${Math.round(m)} m` : `${(m / 1000).toFixed(1).replace('.', ',')} km`;
}

/** { state: 'loading' | 'unavailable' | 'known', meters?, reason? } */
export function useLiveDistance(latitude, longitude) {
  const tanimli = latitude != null && longitude != null;
  const [durum, setDurum] = useState({ state: 'loading' });

  useEffect(() => {
    if (!tanimli) return undefined;
    if (!navigator.geolocation) return undefined;
    const id = navigator.geolocation.watchPosition(
      (p) => setDurum({
        state: 'known',
        meters: distanceMeters(p.coords.latitude, p.coords.longitude, Number(latitude), Number(longitude)),
      }),
      (e) => setDurum({
        state: 'unavailable',
        reason: e.code === 1 ? 'Konum izni yok' : 'Konum alınamadı',
      }),
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 },
    );
    return () => navigator.geolocation.clearWatch(id);
  }, [tanimli, latitude, longitude]);

  if (!tanimli) return { state: 'unavailable', reason: 'Mağaza konumu tanımlı değil' };
  if (!navigator.geolocation) return { state: 'unavailable', reason: 'Konum desteklenmiyor' };
  return durum;
}

/** "GPS: 42 m · sınır 100 m" — sinir icinde yesil, disinda uyari renginde. */
export function LiveDistanceLabel({ latitude, longitude, radiusM, prefix = 'GPS: ', showRadius = true, small = false }) {
  const d = useLiveDistance(latitude, longitude);
  let metin;
  let sinif = 'muted';
  let Ikon = Locate;
  if (d.state === 'loading') {
    metin = `${prefix}konum alınıyor…`;
  } else if (d.state === 'unavailable') {
    metin = `${prefix}${d.reason}`;
    Ikon = LocateOff;
  } else {
    metin = `${prefix}${formatDistance(d.meters)}${showRadius && radiusM ? ` · sınır ${radiusM} m` : ''}`;
    sinif = radiusM && d.meters <= radiusM ? 'text-success' : 'text-warning';
    Ikon = LocateFixed;
  }
  return (
    <span className={`live-distance ${sinif}${small ? ' small' : ''}`} aria-live="polite">
      <Ikon size={small ? 13 : 15} /> {metin}
    </span>
  );
}
