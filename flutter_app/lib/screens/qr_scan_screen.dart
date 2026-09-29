import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/session.dart';
import '../core/tokens.dart';

/// Kamera ile QR okuma sayfası.
///
/// Mağaza içi PDKS doğrulama için modern retail ops tarzında tasarlanmıştır:
/// - Beyaz üst bar, geri butonu, ekran başlığı ve sağda kompakt PIN geçiş butonu
/// - Mağaza konum doğrulama rozeti (Geo-Fence badge: "Düzce Merkez Colombia Coffee 📍")
/// - Işıltılı zümrüt yeşili hedef çerçevesi ve köşe braketleri
/// - Animasyonlu yeşil tarama lazeri
/// - Flaş aç/kapat ve PIN girişi hızlı aksiyon hap butonları
/// - Güvenlik & gizlilik bilgilendirme alt metni
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.title});

  final String title;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController(
    // Yalnızca QR: barkod türlerini daraltmak yanlış okumayı azaltır.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _manual = TextEditingController();
  late final AnimationController _laserAnim;
  bool _done = false;
  bool _typing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _laserAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _laserAnim.dispose();
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String value) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Color(0xFF0F172A),
                      size: 22,
                    ),
                    tooltip: 'Geri',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() {
                        _typing = !_typing;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _typing
                                  ? Icons.qr_code_scanner_rounded
                                  : Icons.dialpad_outlined,
                              size: 14,
                              color: const Color(0xFF334155),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _typing ? 'Kamera' : 'PIN',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _typing ? _manualEntry(t) : _camera(t),
    );
  }

  Widget _camera(AppTokens t) {
    final storeName = session.user?.storeName ?? 'Mağaza';

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Kamera akışı
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final code = capture.barcodes
                .map((b) => b.rawValue)
                .firstWhere(
                  (v) => v != null && v.isNotEmpty,
                  orElse: () => null,
                );
            if (code != null) _finish(code);
          },
          errorBuilder: (context, error) {
            // Kamera açılamadı: kullanıcıyı elle girişe yönlendir
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.no_photography_outlined,
                        size: 44,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Kamera Açılamadı',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Kamera izni verilmemiş olabilir veya cihaz kamerası kullanılamıyor. Kodu manuel olarak girebilirsiniz.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () => setState(() => _typing = true),
                        icon: const Icon(Icons.dialpad_outlined, size: 18),
                        label: const Text('PIN / Kod ile Giriş'),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.primary,
                          foregroundColor: t.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // 2. Hafif koyuluk ve radial vignette
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.88),
                  ],
                  stops: const [0.3, 0.75, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 3. Ön katman arayüzü
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxSize = math.min(270.0, constraints.maxWidth - 64.0);

              return Column(
                children: [
                  const SizedBox(height: 14),

                  // Konum doğrulama rozeti (Store Geo-Fence Badge)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0F172A),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _PulsingDot(),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '$storeName 📍',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6EE7B7),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Merkezi QR hedef alanı
                  Center(
                    child: SizedBox(
                      width: boxSize,
                      height: boxSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Dış çerçeve ve ışıma
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: t.primary.withValues(alpha: 0.9),
                                width: 2,
                              ),
                              color: t.primaryDark.withValues(alpha: 0.05),
                              boxShadow: [
                                BoxShadow(
                                  color: t.primarySoft.withValues(alpha: 0.25),
                                  blurRadius: 24,
                                  spreadRadius: 1,
                                ),
                                BoxShadow(
                                  color: t.primarySoft.withValues(alpha: 0.12),
                                  blurRadius: 12,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                          ),

                          // 4 Köşe Vurgusu (Corner Accents)
                          const _CornerAccent(
                            alignment: Alignment.topLeft,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(14),
                            ),
                          ),
                          const _CornerAccent(
                            alignment: Alignment.topRight,
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(14),
                            ),
                          ),
                          const _CornerAccent(
                            alignment: Alignment.bottomLeft,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(14),
                            ),
                          ),
                          const _CornerAccent(
                            alignment: Alignment.bottomRight,
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(14),
                            ),
                          ),

                          // Merkez Nişangahı (Crosshair)
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFF34D399)
                                    .withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Container(
                                width: 4.5,
                                height: 4.5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34D399),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),

                          // Dikey tarama lazer çizgisi
                          AnimatedBuilder(
                            animation: _laserAnim,
                            builder: (context, _) {
                              final topOffset =
                                  16.0 + (_laserAnim.value * (boxSize - 34.0));
                              return Positioned(
                                top: topOffset,
                                left: 14,
                                right: 14,
                                child: Container(
                                  height: 2,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Color(0xFF34D399),
                                        Colors.transparent,
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF34D399)
                                            .withValues(alpha: 0.8),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Kamera Kontrolleri: Flaş Aç & PIN Girişi
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ValueListenableBuilder<MobileScannerState>(
                        valueListenable: _controller,
                        builder: (context, state, _) {
                          final isTorchOn = state.torchState == TorchState.on;

                          return _ControlPillButton(
                            icon: Icon(
                              Icons.bolt_rounded,
                              size: 16,
                              color: isTorchOn
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFFBBF24),
                            ),
                            label: isTorchOn ? 'Flaş Kapat' : 'Flaş Aç',
                            onTap: () => _controller.toggleTorch(),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      _ControlPillButton(
                        icon: const Icon(
                          Icons.key_rounded,
                          size: 15,
                          color: Color(0xFFE2E8F0),
                        ),
                        label: 'PIN Girişi',
                        onTap: () => setState(() => _typing = true),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Alt bilgilendirme ve gizlilik metni
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'QR kodu çerçeveye alın.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Kamera görüntüsü cihazdan çıkmıyor, sunucuya gönderilmiyor.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _manualEntry(AppTokens t) {
    final pin = _manual.text;
    void digit(String value) {
      if (_manual.text.length >= 6) return;
      setState(() {
        _manual.text += value;
        _error = null;
      });
    }

    return ColoredBox(
      color: const Color(0xFFF5F7FC),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: t.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.dialpad_outlined,
                          size: 22,
                          color: t.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Store Manager PIN Onayı',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Kamera veya QR arızasında mağaza PIN’ini girin',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: t.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: t.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: t.dangerStrong,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: t.dangerStrong,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      6,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 44,
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: index < pin.length
                              ? t.primarySoft
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: index <= pin.length
                                ? t.primary
                                : const Color(0xFFE2E8F0),
                            width: index == pin.length ? 1.8 : 1,
                          ),
                        ),
                        child: Text(
                          index < pin.length ? pin[index] : '•',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: index < pin.length
                                ? t.primary
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    childAspectRatio: 2.05,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (final value in const [
                        '1',
                        '2',
                        '3',
                        '4',
                        '5',
                        '6',
                        '7',
                        '8',
                        '9',
                      ])
                        OutlinedButton(
                          onPressed: () => digit(value),
                          child: Text(value),
                        ),
                      OutlinedButton(
                        onPressed: () {},
                        child: Icon(
                          Icons.fingerprint_rounded,
                          color: t.primary,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => digit('0'),
                        child: const Text('0'),
                      ),
                      OutlinedButton(
                        onPressed: pin.isEmpty
                            ? null
                            : () => setState(() {
                                _manual.text = pin.substring(0, pin.length - 1);
                                _error = null;
                              }),
                        child: const Icon(Icons.backspace_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () {
                      final v = _manual.text.trim();
                      if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                        setState(() => _error = 'PIN tam 6 rakam olmalıdır');
                        return;
                      }
                      _finish(v);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: t.primary,
                      foregroundColor: t.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'PIN ile Mesaiyi Onayla',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kamera kontrolleri için yarı saydam hap buton
class _ControlPillButton extends StatelessWidget {
  const _ControlPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Çerçeve köşelerindeki kalın vurgu braketleri
class _CornerAccent extends StatelessWidget {
  const _CornerAccent({required this.alignment, required this.borderRadius});

  final Alignment alignment;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;

    return Positioned(
      top: isTop ? 4 : null,
      bottom: !isTop ? 4 : null,
      left: isLeft ? 4 : null,
      right: !isLeft ? 4 : null,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border(
            top: isTop
                ? BorderSide(color: t.primary, width: 3.8)
                : BorderSide.none,
            bottom: !isTop
                ? BorderSide(color: t.primary, width: 3.8)
                : BorderSide.none,
            left: isLeft
                ? BorderSide(color: t.primary, width: 3.8)
                : BorderSide.none,
            right: !isLeft
                ? BorderSide(color: t.primary, width: 3.8)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Geo-fence rozetindeki yanıp sönen yeşil sinyal noktası
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 10,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              return Container(
                width: 6.0 + (_anim.value * 4.0),
                height: 6.0 + (_anim.value * 4.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF34D399)
                      .withValues(alpha: (1.0 - _anim.value).clamp(0.0, 0.6)),
                ),
              );
            },
          ),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF34D399),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
