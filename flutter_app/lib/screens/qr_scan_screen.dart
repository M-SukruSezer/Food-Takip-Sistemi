import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/tokens.dart';
import '../widgets/dialogs.dart';

/// Kamera ile QR okuma sayfasi.
///
/// Kamera acilamazsa (izin yok, cihazda kamera yok) elle giris kaliyor:
/// kiosk ekranindaki kod okunabilir bicimde de yaziliyor.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.title});

  final String title;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    // Yalnizca QR: barkod turlerini daraltmak yanlis okumayi azaltiyor.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _manual = TextEditingController();
  bool _done = false;
  bool _typing = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String value) {
    // noDuplicates kamerayi susturuyor ama yine de tek cikis garantilenir.
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: t.card,
        foregroundColor: t.ink,
        actions: [
          IconButton(
            tooltip: _typing ? 'Kameraya dön' : 'Elle gir',
            onPressed: () => setState(() => _typing = !_typing),
            icon: Icon(_typing ? Icons.photo_camera_outlined : Icons.keyboard),
          ),
        ],
      ),
      body: _typing ? _manualEntry(t) : _camera(t),
    );
  }

  Widget _camera(AppTokens t) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final code = capture.barcodes
                .map((b) => b.rawValue)
                .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
            if (code != null) _finish(code);
          },
          errorBuilder: (context, error) {
            // Kamera acilamadi: kullaniciyi elle girise yonlendir.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.no_photography_outlined, size: 40, color: t.card),
                    const SizedBox(height: 12),
                    Text(
                      'Kamera açılamadı. Kodu elle girebilirsiniz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.card, fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => setState(() => _typing = true),
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Elle Gir'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Hedef cercevesi: kullanici kodu nereye tutacagini bilsin.
        IgnorePointer(
          child: Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'QR kodu çerçeveye alın.\n'
              'Kamera görüntüsü cihazdan çıkmıyor, sunucuya gönderilmiyor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _manualEntry(AppTokens t) {
    return ColoredBox(
      color: t.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: t.danger)),
              const SizedBox(height: 12),
            ],
            LabeledField(
              label: 'QR Kod Metni',
              hint: 'Kiosk ekranındaki kodun altında yazan metni girin.',
              child: TextField(
                controller: _manual,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(hintText: 'PDKS1:...'),
              ),
            ),
            FilledButton(
              onPressed: () {
                final v = _manual.text.trim();
                if (v.isEmpty) {
                  setState(() => _error = 'Kod metni zorunludur');
                  return;
                }
                _finish(v);
              },
              child: const Text('Onayla'),
            ),
          ],
        ),
      ),
    );
  }
}
