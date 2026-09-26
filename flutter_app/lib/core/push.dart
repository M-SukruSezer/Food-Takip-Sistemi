import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository.dart';
import 'session.dart';

/// Telefon bildirimleri.
///
/// KAPSAM — ne yapiyor, ne YAPMIYOR:
///   YAPIYOR   Uygulama acikken (on planda ya da arka planda calisirken)
///             sunucudaki yeni bildirimleri gorup TELEFONUN kendi bildirim
///             merkezine dusuruyor. Vardiya paylasimi, vardiya degisikligi,
///             talep olusturma ve talep kararlari bu yoldan geliyor.
///   YAPMIYOR  Uygulama TAMAMEN kapaliyken bildirim gonderemiyor. Bunun icin
///             Firebase Cloud Messaging gerekiyor ve FCM isletmenin kendi
///             Firebase projesini, google-services.json dosyasini ve sunucu
///             anahtarini istiyor. O dosya elimizde olmadigi icin bu katman
///             yoklamaya (polling) dayaniyor.
///
/// Sunucu tarafi buna hazir: bildirimler notify.js'te TASIYICI desenine gore
/// yayinlaniyor. FCM baglanacagi zaman oraya bir tasiyici eklemek yetiyor,
/// cagiran kodun hicbiri degismiyor.

const _kanalId = 'operasyon_takip_bildirim';
const _kanalAdi = 'Vardiya ve talep bildirimleri';
const _kanalAciklama =
    'Haftalık vardiya paylaşımı, vardiya değişikliği ve talep durumu.';

/// En son bildirilen kayit kimligi. Kullanici basina ayri tutuluyor: ayni
/// telefonda baska biri giris yaptiginda onceki kullanicinin okunmuslugu
/// devralinmamali.
String _sonAnahtar(int userId) => 'bildirim_son_id_$userId';

final FlutterLocalNotificationsPlugin _eklenti =
    FlutterLocalNotificationsPlugin();

bool _hazir = false;

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
    _hazir = true;
  } catch (_) {
    // Bildirim kurulamazsa uygulama CALISMAYA DEVAM ETMELI: bildirim bir yan
    // ozellik, vardiya girisini engellemesi kabul edilemez.
    _hazir = false;
  }
}

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
