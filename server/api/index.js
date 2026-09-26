const { app, initialize } = require('../src/index');

// Sema hazirligi istek basina degil ORNEK basina bir kez yapilir; her istekte
// tum semayi yeniden calistirmak soguk olmayan istekleri de yavaslatirdi.
let ready = null;

module.exports = async (req, res) => {
  try {
    // Onbellege YALNIZCA basarili hazirlik alinir. Onceki hali `ready ||=`
    // idi ve REDDEDILMIS sozu de sakliyordu: hazirlik bir kez hata alinca
    // o sicak ornek, sebep ortadan kalksa bile her istege 500 donuyordu.
    // Olculdu: semadaki tek bir ifade hata verdiginde API, hata giderildikten
    // sonra da ornek geri donusturulene kadar ayakta kalmadi.
    if (!ready) ready = initialize();
    await ready;
  } catch (error) {
    // Bir sonraki istek yeniden denesin.
    ready = null;
    console.error('Veritabanı hazırlığı başarısız:', error);
    return res.status(503).json({
      error: 'Sistem başlatılıyor, lütfen birkaç saniye sonra tekrar deneyin',
    });
  }
  return app(req, res);
};
