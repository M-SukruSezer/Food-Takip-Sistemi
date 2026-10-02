import { useEffect, useRef, useState } from 'react';
import { X, Keyboard, Hash, ScanLine, MapPin } from 'lucide-react';
import { LiveDistanceLabel } from './LiveDistance';

// Kamera ile QR okuyucu.
//
// Kamera erisimi reddedilirse ya da cihazda kamera yoksa elle giris secenegi
// kaliyor: kiosk ekranindaki kod okunabilir bicimde de yaziliyor.
//
// QR okutulamazsa "PIN ile Giriş": magaza muduru / vardiya sorumlusunun
// PIN Dogrulama ekranindaki 60 sn'lik 6 haneli kod girilir.
/// Ust bar: magaza ve magazaya CANLI uzaklik (uygulamadaki QR ekrani gibi).
function MagazaSeridi({ store }) {
  if (!store) return null;
  return (
    <div className="qr-store-bar">
      <MapPin size={14} />
      <span>{store.name || 'Mağaza'}</span>
      {store.has_location && (
        <LiveDistanceLabel
          latitude={store.latitude}
          longitude={store.longitude}
          radiusM={store.geofence_radius_m}
          prefix="· "
          showRadius={false}
          small
        />
      )}
    </div>
  );
}

export default function QrScanner({ onResult, onClose, store = null }) {
  const [pinMode, setPinMode] = useState(false);
  const [pin, setPin] = useState('');
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const [err, setErr] = useState('');
  const [manual, setManual] = useState(false);
  const [text, setText] = useState('');
  const [tarama, setTarama] = useState(false);

  useEffect(() => {
    if (manual || pinMode) return undefined;
    let stream = null;
    let raf = null;
    let iptal = false;
    let decode = null;

    async function baslat() {
      try {
        const mod = await import('jsqr');
        decode = mod.default || mod;
        stream = await navigator.mediaDevices.getUserMedia({
          // Arka kamera: QR kodu okuturken kullanilan kamera.
          video: { facingMode: 'environment' },
        });
        if (iptal) { stream.getTracks().forEach((t) => t.stop()); return; }
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
        setTarama(true);
        tick();
      } catch (e) {
        setErr(
          e && e.name === 'NotAllowedError'
            ? 'Kamera izni verilmedi. Kodu elle girebilirsiniz.'
            : 'Kamera açılamadı. Kodu elle girebilirsiniz.'
        );
        setManual(true);
      }
    }

    function tick() {
      if (iptal) return;
      const v = videoRef.current;
      const c = canvasRef.current;
      if (v && c && v.readyState === v.HAVE_ENOUGH_DATA) {
        c.width = v.videoWidth;
        c.height = v.videoHeight;
        const ctx = c.getContext('2d', { willReadFrequently: true });
        ctx.drawImage(v, 0, 0, c.width, c.height);
        const img = ctx.getImageData(0, 0, c.width, c.height);
        const found = decode(img.data, img.width, img.height, {
          inversionAttempts: 'dontInvert',
        });
        if (found && found.data) {
          onResult(found.data);
          return;
        }
      }
      raf = requestAnimationFrame(tick);
    }

    baslat();
    return () => {
      iptal = true;
      if (raf) cancelAnimationFrame(raf);
      if (stream) stream.getTracks().forEach((t) => t.stop());
    };
  }, [manual, pinMode, onResult]);

  if (pinMode) {
    return (
      <div className="qr-scanner">
        <MagazaSeridi store={store} />
        <div className="field">
          <label>PIN Doğrulama</label>
          <input
            value={pin}
            onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
            inputMode="numeric"
            autoComplete="one-time-code"
            placeholder="______"
            className="pin-input"
            autoFocus
          />
          <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '4px 0 0' }}>
            Mağaza müdürü veya vardiya sorumlusunun ekranındaki 60 sn’lik kodu girin.
          </p>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={() => setPinMode(false)}>
            <ScanLine size={16} /> QR ile Giriş
          </button>
          <button type="button" className="btn btn-primary" disabled={pin.length !== 6}
            onClick={() => onResult(pin)}>
            PIN ile Onayla
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="qr-scanner">
      <MagazaSeridi store={store} />
      {!manual && (
        <>
          <div className="qr-viewport">
            <video ref={videoRef} playsInline muted />
            <canvas ref={canvasRef} style={{ display: 'none' }} />
            <div className="qr-frame" />
          </div>
          <p className="muted" style={{ fontSize: 'var(--fs-body)', margin: '8px 0 0' }}>
            {tarama ? 'QR kodu çerçeveye alın' : 'Kamera açılıyor...'}
          </p>
        </>
      )}
      {err && <div className="alert error" style={{ marginTop: 10 }}>{err}</div>}

      {manual && (
        <div className="field">
          <label>QR Kod Metni</label>
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="PDKS1:..."
            autoFocus
          />
          <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '4px 0 0' }}>
            Kiosk ekranındaki kodun altında yazan metni girin.
          </p>
        </div>
      )}

      <div className="form-actions">
        <button type="button" className="btn btn-secondary" onClick={onClose}>
          <X size={16} /> Vazgeç
        </button>
        <button type="button" className="btn btn-secondary" onClick={() => setPinMode(true)}>
          <Hash size={16} /> PIN ile Giriş
        </button>
        {manual ? (
          <button type="button" className="btn btn-primary" disabled={!text.trim()}
            onClick={() => onResult(text.trim())}>
            Onayla
          </button>
        ) : (
          <button type="button" className="btn btn-secondary" onClick={() => setManual(true)}>
            <Keyboard size={16} /> Elle Gir
          </button>
        )}
      </div>
    </div>
  );
}
