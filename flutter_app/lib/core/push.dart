import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository.dart';
import 'session.dart';

/// Telefon bildirimleri.
///
/// IKI YOL birlikte calisiyor:
///
///   1. FCM (asil yol) — uygulama kapaliyken bile bildirim geliyor.
///      Sunucu 'notification' + 'data' gonderiyor:
///        • uygulama KAPALI/ARKA PLANDA  -> bildirimi Android kendisi gosterir
///        • uygulama ON PLANDA           -> onMessage tetiklenir, bildirimi
///                                          biz gosteririz (Android on planda
///                                          kendiliginden gostermez)
///
///   2. Yoklama (emniyet agi) — FCM teslimat GARANTISI VERMEZ: token
///      yenilenmesi, Google Play Services olmayan cihazlar, pil
///      iyilestirmeleri ve ag kesintileri bildirimi dusurebilir. Yoklayici
///      uygulama acikken kacan bildirimleri yakaliyor.
///
/// TEKRAR: iki yol ayni bildirimi iki kez gostermemeli. Iki onlem var —
///   • Bildirim kimligi, isletim sistemi bildirim kimligi olarak
///     KULLANILIYOR. Ayni kimlikle ikinci gosterim yenisini eklemez,
///     mevcudu degistirir.
///   • FCM bir bildirimi isledigi anda (on planda da, arka plan
///     izolesinde de) "en son gorulen" isareti ilerletiliyor; yoklayici
///     o bildirimi bir daha gostermiyor.

const _kanalId = 'operasyon_takip_bildirim';
const _kanalAdi = 'Vardiya ve talep bildirimleri';
const _kanalAciklama =
    'Haftalık vardiya paylaşımı, vardiya değişikliği ve talep durumu.';

/// En son bildirilen kayit kimligi. Kullanici basina ayri tutuluyor: ayni
/// telefonda baska biri giris yaptiginda onceki kullanicinin okunmuslugu
/// devralinmamali.
String _sonAnahtar(int userId) => 'bildirim_son_id_$userId';

/// FCM'den gelen bildirimin kimligini "en son gorulen" isaretine isler.
///
/// Boylece yoklayici ayni bildirimi bir daha gostermiyor. Arka plan
/// izolesinden de cagriliyor: orada [session] YUKLU DEGIL, bu yuzden
/// kullanici kimligi mesajin kendisinden okunuyor.
Future<void> _isaretiIlerlet(int? userId, int? bildirimId) async {
  if (userId == null || bildirimId == null) return;
  try {
    final sp = await SharedPreferences.getInstance();
    final anahtar = _sonAnahtar(userId);
    final mevcut = sp.getInt(anahtar) ?? 0;
    if (bildirimId > mevcut) await sp.setInt(anahtar, bildirimId);
  } catch (_) {
    // Disk yazilamadi: en kotu ihtimalle yoklayici bildirimi bir kez daha
    // gosterir. Ayni kimlik kullanildigi icin yeni bir satir eklenmez.
  }
}

int? _sayi(Object? v) => v == null ? null : int.tryParse(v.toString());

/// Testlerin isaret ilerletmeyi dogrulamasi icin. Gercek FCM isleyicisi
/// [RemoteMessage] istiyor ve o nesne test ortaminda platform kanali
/// olmadan uretilemiyor; islenen mantik ise ayni.
@visibleForTesting
Future<void> firebaseArkaPlanMesajiTest({
  required int userId,
  required int notificationId,
}) => _isaretiIlerlet(userId, notificationId);

/// Arka plan / kapali uygulama mesaj isleyicisi.
///
/// AYRI IZOLEDE calisiyor: uygulamanin belleginden hicbir seye erisemez.
/// Bildirimi Android zaten gosteriyor; burada yalnizca isaret ilerletiliyor
/// ki uygulama acildiginda yoklayici ayni bildirimi tekrar gostermesin.
@pragma('vm:entry-point')
Future<void> firebaseArkaPlanMesaji(RemoteMessage mesaj) async {
  await _isaretiIlerlet(
    _sayi(mesaj.data['user_id']),
    _sayi(mesaj.data['notification_id']),
  );
}

final FlutterLocalNotificationsPlugin _eklenti =
    FlutterLocalNotificationsPlugin();

bool _hazir = false;
bool _fcmHazir = false;

/// Bildirim altyapisini kurar. Birden fazla cagrilabilir.
///
/// Testte ve web'de HICBIR SEY yapmaz: platform kanali yok, kurulum
/// denemesi yalnizca hata uretirdi.
Future<void> initPush() async {
  if (_hazir || kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  try {
    await _eklenti.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    // Android'de kanali ONCEDEN olusturuyoruz. FCM arka planda bildirimi
    // kendisi gosterirken bu kanali kullaniyor; kanal yoksa Android
    // varsayilan (sessiz, dusuk oncelikli) kanala dusurur.
    await _eklenti
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _kanalId,
            _kanalAdi,
            description: _kanalAciklama,
            importance: Importance.high,
          ),
        );
    _hazir = true;
  } catch (_) {
    // Bildirim kurulamazsa uygulama CALISMAYA DEVAM ETMELI: bildirim bir yan
    // ozellik, vardiya girisini engellemesi kabul edilemez.
    _hazir = false;
  }

  // Firebase AYRI try: bildirim altyapisi kurulduysa FCM patlasa bile
  // yoklama yolu calismaya devam etmeli.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseArkaPlanMesaji);

    // On plandaki mesaj: Android kendiliginden GOSTERMEZ, biz gosteriyoruz.
    FirebaseMessaging.onMessage.listen((mesaj) async {
      final id = _sayi(mesaj.data['notification_id']);
      await _isaretiIlerlet(_sayi(mesaj.data['user_id']), id);
      final n = mesaj.notification;
      if (n == null) return;
      await _goster(id ?? DateTime.now().millisecondsSinceEpoch % 100000,
          n.title ?? 'Bildirim', n.body ?? '');
    });

    _fcmHazir = true;
  } catch (_) {
    // Google Play Services yok, yapilandirma eksik ya da ag kapali.
    // Yoklama yolu devrede kalir.
    _fcmHazir = false;
  }
}

/// FCM kullanilabilir mi. Yoklayici bunu BILMEK ZORUNDA DEGIL — emniyet agi
/// olarak her durumda calisiyor — ama tanilama ve gunluk icin duruyor.
bool get fcmHazir => _fcmHazir;

/// Bildirim iznini ister. Android 13+ ve iOS'ta gerekli.
///
/// Reddedilirse sessizce gecilir; uygulama ici bildirim listesi yine calisir.
Future<void> requestPushPermission() async {
  if (!_hazir) return;
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _eklenti
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else {
      await _eklenti
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  } catch (_) {
    // Izin alinamadi; bildirim gosterilmez, akis bozulmaz.
  }
}

/// Bu cihazin FCM jetonunu sunucuya kaydeder.
///
/// Sunucu jetonu KULLANICIYA bagli tutuyor: ayni telefonda baska biri giris
/// yaptiginda jeton yeni kullaniciya gecmeli, yoksa bildirimler onceki
/// kisinin hesabina gitmeye devam eder.
///
/// Jeton YENILENEBILIR (uygulama verisi silinince, yeniden kurulumda,
/// Google'in kendi dondurmesiyle). onTokenRefresh dinleniyor: yenilenen
/// jeton kaydedilmezse o cihaz sessizce bildirim almaz hale gelir.
StreamSubscription<String>? _jetonAboneligi;

Future<void> registerDeviceToken() async {
  if (!_fcmHazir) return;
  try {
    final jeton = await FirebaseMessaging.instance.getToken();
    if (jeton != null && jeton.isNotEmpty) {
      await repo.pdksRegisterDevice(jeton);
    }
    await _jetonAboneligi?.cancel();
    _jetonAboneligi = FirebaseMessaging.instance.onTokenRefresh.listen((y) {
      unawaited(repo.pdksRegisterDevice(y).catchError((_) {}));
    });
  } catch (_) {
    // Jeton alinamadi: FCM calismaz, yoklama yolu devrede kalir.
  }
}

/// Cikista jetonu SUNUCUDAN siler.
///
/// Silinmezse telefon, oturumu kapatmis kullanicinin bildirimlerini almaya
/// devam eder — baska birinin vardiya bilgisi yanlis kisiye duser.
Future<void> unregisterDeviceToken() async {
  await _jetonAboneligi?.cancel();
  _jetonAboneligi = null;
  if (!_fcmHazir) return;
  try {
    final jeton = await FirebaseMessaging.instance.getToken();
    if (jeton != null && jeton.isNotEmpty) {
      await repo.pdksUnregisterDevice(jeton);
    }
  } catch (_) {
    // Silinemedi: sunucu tarafi gecersiz jetonlari FCM'in UNREGISTERED
    // yanitiyla da temizliyor.
  }
}

/// Tek bildirimi telefonun bildirim merkezine dusurur.
Future<void> _goster(int id, String baslik, String govde) async {
  if (!_hazir) return;
  try {
    await _eklenti.show(
      id: id,
      title: baslik,
      body: govde,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _kanalId,
          _kanalAdi,
          channelDescription: _kanalAciklama,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  } catch (_) {
    // Tek bildirim dusmezse digerleri denenmeye devam etsin.
  }
}

/// Sunucudaki yeni bildirimleri telefona dusuren yoklayici.
///
/// TEKRAR ETMEME: en son gosterilen kaydin kimligi diske yaziliyor. Uygulama
/// yeniden acildiginda ayni bildirimler bir daha gosterilmiyor — aksi halde
/// her acilista eski bildirimler yeniden dokulurdu.
class PushPoller {
  PushPoller({this.aralik = const Duration(seconds: 90)});

  final Duration aralik;
  Timer? _zamanlayici;
  bool _calisiyor = false;

  /// Okunmamis bildirim sayisi degistiginde tetiklenir (rozet icin).
  final ValueNotifier<int> okunmamis = ValueNotifier<int>(0);

  void start() {
    stop();
    // Ilk yoklama hemen: uygulama acilirken bekleyen bildirim varsa
    // bir buçuk dakika beklemeden gorunsun.
    unawaited(_yokla());
    _zamanlayici = Timer.periodic(aralik, (_) => unawaited(_yokla()));
  }

  void stop() {
    _zamanlayici?.cancel();
    _zamanlayici = null;
  }

  void dispose() {
    stop();
    okunmamis.dispose();
  }

  Future<void> _yokla() async {
    // Ust uste calismasin: yavas ag baglantisinda istekler birikirdi.
    if (_calisiyor) return;
    final user = session.user;
    if (user == null) return;
    _calisiyor = true;
    try {
      final liste = await repo.pdksNotifications(limit: 20);
      okunmamis.value = liste.unread;
      if (liste.items.isEmpty) return;

      final sp = await SharedPreferences.getInstance();
      final anahtar = _sonAnahtar(user.id);
      final sonGorulen = sp.getInt(anahtar);

      // ILK CALISMA: gecmisi telefona dokme. Hesap acildiginda birikmis
      // bildirimlerin hepsini bildirim merkezine bosaltmak kullanilamaz bir
      // gurultu olurdu; yalnizca isaret birakilip bundan sonrasi gosteriliyor.
      final enBuyuk = liste.items
          .map((n) => n.id)
          .reduce((a, b) => a > b ? a : b);
      if (sonGorulen == null) {
        await sp.setInt(anahtar, enBuyuk);
        return;
      }

      // Eskiden yeniye: bildirim merkezinde dogru sirada gorunsun.
      final yeniler = liste.items.where((n) => n.id > sonGorulen).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final n in yeniler) {
        await _goster(n.id, n.title, n.body);
      }
      if (enBuyuk > sonGorulen) await sp.setInt(anahtar, enBuyuk);
    } catch (_) {
      // Ag hatasi sessiz: yoklama arka planda, kullaniciya hata gostermek
      // anlamsiz. Sonraki turda tekrar denenir.
    } finally {
      _calisiyor = false;
    }
  }
}

/// Tek bildirim kaydi.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.data,
  });

  final int id;
  final String kind;
  final String title;
  final String body;
  final bool read;
  final String createdAt;
  final Map<String, dynamic>? data;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: (j['id'] as num?)?.toInt() ?? 0,
    kind: j['kind'] as String? ?? '',
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
    read: j['read'] == true,
    createdAt: j['created_at'] as String? ?? '',
    data: switch (j['data']) {
      final Map<String, dynamic> m => m,
      final String s when s.isNotEmpty =>
        jsonDecode(s) as Map<String, dynamic>?,
      _ => null,
    },
  );
}

/// Bildirim listesi ve okunmamis sayisi.
class NotificationList {
  const NotificationList({required this.unread, required this.items});

  final int unread;
  final List<AppNotification> items;
}
