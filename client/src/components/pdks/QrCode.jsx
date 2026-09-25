import { useEffect, useRef, useState } from 'react';

// QR kod gostericisi.
//
// qrcode paketi canvas'a ciziyor; bagimlilik yalnizca bu bilesen acildiginda
// indirilsin diye dinamik import kullaniliyor (paket boyutu normal
// kullanimda buyumesin).
export default function QrCode({ value, size = 220, label }) {
  const canvasRef = useRef(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    let iptal = false;
    if (!value) return undefined;
    import('qrcode')
      .then((mod) => {
        if (iptal || !canvasRef.current) return;
        const QRCode = mod.default || mod;
        return QRCode.toCanvas(canvasRef.current, value, {
          width: size,
          margin: 2,
          errorCorrectionLevel: 'M',
        });
      })
      .then(() => { if (!iptal) setErr(''); })
      .catch(() => { if (!iptal) setErr('QR kod oluşturulamadı'); });
    return () => { iptal = true; };
  }, [value, size]);

  if (err) return <div className="alert error">{err}</div>;
  return (
    <div className="qr-box">
      {/* Beyaz zemin zorunlu: koyu temada QR okunamaz hale gelir. */}
      <canvas ref={canvasRef} width={size} height={size} />
      {label && <p className="qr-label">{label}</p>}
    </div>
  );
}
