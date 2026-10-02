import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/notify.dart';
import '../core/device_integrity.dart';
import '../core/pdks_location.dart';
import '../core/repository.dart';
import '../models/pdks.dart';
import '../screens/qr_scan_screen.dart';

final pdksChanges = ValueNotifier<int>(0);

Future<void> performPdksQr(BuildContext context, PdksPunch adim) async {
  final basliklar = {
    PdksPunch.checkIn: 'QR ile Giriş',
    PdksPunch.checkOut: 'QR ile Çıkış',
    PdksPunch.breakStart: 'QR ile Mola Başlangıcı',
    PdksPunch.breakEnd: 'QR ile Mola Bitişi',
  };
  final token = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) =>
          QrScanScreen(title: basliklar[adim] ?? 'QR Okut', pdks: true),
    ),
  );
  if (token == null || !context.mounted) return;

  try {
    // Konum ZORUNLU: QR "kodu okuttu" der, konum "IS YERINDE okuttu" der.
    // Cihaz kontrolu konumla PARALEL yurutulur; seri yapilsa bekleme iki
    // islemin toplami olurdu.
    final sonuclar = await Future.wait([
      currentPosition(),
      readDeviceIntegrity(),
    ]);
    final pos = sonuclar[0] as PdksPosition;
    final integrity = sonuclar[1] as DeviceIntegrity;
    await repo.pdksPunchQr(
      adim: adim,
      token: token,
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      // Android'in bu OLCUM icin verdigi sahte konum karari. Sunucu
      // true ise kaydi REDDEDIYOR.
      isMocked: pos.isMocked,
      integrity: integrity,
    );
    toastSaved(adim.mesaj);
    if (integrity.warnings.isNotEmpty) {
      toast(
        'Kayıt alındı, not düşüldü: ${integrity.warnings.join(', ')}',
        kind: ToastKind.warning,
      );
    }
    pdksChanges.value++;
  } on LocationDenied catch (e) {
    toast(e.message, kind: ToastKind.error);
  } catch (e) {
    toast(errorMessage(e), kind: ToastKind.error);
  }
}
