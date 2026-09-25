import { useEffect, useRef, useState } from 'react';
import { Camera, X, Keyboard } from 'lucide-react';

// Kamera ile QR okuyucu.
//
// Kamera erisimi reddedilirse ya da cihazda kamera yoksa elle giris secenegi
// kaliyor: kiosk ekranindaki kod okunabilir bicimde de yaziliyor.
export default function QrScanner({ onResult, onClose }) {
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const [err, setErr] = useState('');
  const [manual, setManual] = useState(false);
  const [text, setText] = useState('');
  const [tarama, setTarama] = useState(false);

  useEffect(() => {
    if (manual) return undefined;
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
  }, [manual, onResult]);

  return (
    <div className="qr-scanner">
      {!manual && (
        <>
          <div className="qr-viewport">
            <video ref={videoRef} playsInline muted />
            <canvas ref={canvasRef} style={{ display: 'none' }} />
            <div className="qr-frame" />
          </div>
          <p className="muted" style={{ fontSize: 13, margin: '8px 0 0' }}>
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
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            Kiosk ekranındaki kodun altında yazan metni girin.
          </p>
        </div>
      )}

      <div className="form-actions">
        <button type="button" className="btn btn-secondary" onClick={onClose}>
          <X size={16} /> Vazgeç
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
      {!manual && !err && (
        <p className="muted" style={{ fontSize: 12, margin: 0, display: 'flex', gap: 6 }}>
          <Camera size={14} /> Kamera görüntüsü cihazdan çıkmıyor, sunucuya gönderilmiyor.
        </p>
      )}
    </div>
  );
}
