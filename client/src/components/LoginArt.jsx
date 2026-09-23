// Giris ekranindaki illustrasyon.
//
// Sabit bir raster gorsel (public/login-art.png): eller beyaz dolgulu ve
// siyah konturlu, zemini saydam. Bu yuzden her zaman acik bir kart uzerinde
// gosterilir — koyu kartta siyah konturlar kaybolurdu.
export default function LoginArt() {
  // Kare sarmalayici: koyu temada arkasina acik daire konuyor (gorselin siyah
  // konturlari lacivert zeminle birlesiyordu).
  return (
    <div className="login-art-wrap">
      <img
        className="login-art"
        src="/login-art.png"
        alt="Çak bir beş illüstrasyonu"
        width="512"
        height="512"
      />
    </div>
  );
}
