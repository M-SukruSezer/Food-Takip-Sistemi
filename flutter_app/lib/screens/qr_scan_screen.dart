import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/pdks.dart';
import '../widgets/live_distance.dart';

/// Kamera ile QR okuma sayfası.
///
/// Mağaza içi PDKS doğrulama için modern retail ops tarzında tasarlanmıştır:
/// - Beyaz üst bar, geri butonu, ekran başlığı ve sağda kompakt PIN geçiş butonu
/// - Mağaza konum doğrulama rozeti (Geo-Fence badge: "Düzce Merkez Colombia Coffee 📍")
/// - Işıltılı zümrüt yeşili hedef çerçevesi ve köşe braketleri
/// - Animasyonlu yeşil tarama lazeri
/// QR okutulamazsa üst bardaki "PIN ile Giriş" ile 6 haneli PIN girilir.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.title, this.pdks = false});

  final String title;

  /// PDKS okutmasi: ust barda magaza ve magazaya canli uzaklik gosterilir.
  final bool pdks;

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
  PdksStore? _store;

  @override
  void initState() {
    super.initState();
    if (widget.pdks) {
      repo
          .pdksStatus(silent: true)
          .then((s) {
            if (mounted) setState(() => _store = s.store);
          })
          .onError((Object _, StackTrace _) {});
    }
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
      backgroundColor: t.bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: BoxDecoration(
            color: t.card,
            border: Border(bottom: BorderSide(color: t.border, width: 1)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
              child: Row(
                children: [
                  _HeaderCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.pdks ? 'QR ile Giriş' : widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w800,
                            color: t.ink,
                            letterSpacing: -0.35,
                          ),
                        ),
                        if (widget.pdks)
                          // Magaza ve magazaya CANLI uzaklik.
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: t.primary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  _store?.name ??
                                      session.user?.storeName ??
                                      'Mağaza',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppFontSize.caption,
                                    fontWeight: FontWeight.w600,
                                    color: t.muted,
                                  ),
                                ),
                              ),
                              if (_store != null) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: LiveDistanceLabel(
                                    latitude: _store!.latitude,
                                    longitude: _store!.longitude,
                                    radiusM: _store!.geofenceRadiusM,
                                    prefix: '',
                                    showRadius: false,
                                    fontSize: AppFontSize.caption,
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _HeaderPillButton(
                    icon: _typing
                        ? Icons.qr_code_scanner_rounded
                        : Icons.pin_outlined,
                    label: _typing ? 'QR ile Giriş' : 'PIN ile Giriş',
                    onTap: () => setState(() {
                      _typing = !_typing;
                      _error = null;
                    }),
                  ),
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
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _GridBackgroundPainter(
              glow: t.primary,
              color: t.border.withValues(alpha: .56),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boxSize = math.min(290.0, constraints.maxWidth - 94.0);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(top: 20, child: const _InstructionPill()),
                    Positioned(
                      top: math.max(160, constraints.maxHeight * .25),
                      child: SizedBox(
                        width: boxSize,
                        height: boxSize,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: t.card,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: context.tokens.primary.withValues(
                                    alpha: .45,
                                  ),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.tokens.primary600.withValues(
                                      alpha: .15,
                                    ),
                                    blurRadius: 24,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: MobileScanner(
                                  controller: _controller,
                                  fit: BoxFit.cover,
                                  onDetect: (capture) {
                                    final code = capture.barcodes
                                        .map((b) => b.rawValue)
                                        .firstWhere(
                                          (v) => v != null && v.isNotEmpty,
                                          orElse: () => null,
                                        );
                                    if (code != null) _finish(code);
                                  },
                                  errorBuilder: (context, error) => Container(
                                    color: t.bg,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.no_photography_outlined,
                                          color: t.muted,
                                          size: 34,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Kamera kullanılamıyor',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: t.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextButton(
                                          onPressed: () =>
                                              setState(() => _typing = true),
                                          child: const Text('PIN ile devam et'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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

                            // Merkez nişangahı
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: context.tokens.success.withValues(
                                    alpha: 0.35,
                                  ),
                                  width: 1.2,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Container(
                                  width: 4.5,
                                  height: 4.5,
                                  decoration: BoxDecoration(
                                    color: context.tokens.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),

                            // Hareketli tarama çizgisi
                            AnimatedBuilder(
                              animation: _laserAnim,
                              builder: (context, _) {
                                final topOffset =
                                    18.0 +
                                    (_laserAnim.value * (boxSize - 38.0));
                                return Positioned(
                                  top: topOffset,
                                  left: 14,
                                  right: 14,
                                  child: Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          context.tokens.success,
                                          Colors.transparent,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: context.tokens.success
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
                  ],
                );
              },
            ),
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
      color: t.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.border),
                boxShadow: [
                  BoxShadow(
                    color: context.tokens.ink.withValues(alpha: 0.07),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PIN Doğrulama',
                              style: TextStyle(
                                fontSize: AppFontSize.title,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Mağaza müdürü veya vardiya sorumlusunun ekranındaki 60 sn’lik kodu girin',
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                color: t.muted,
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
                            color: t.dangerText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: t.dangerText,
                                fontSize: AppFontSize.label,
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
                          color: index < pin.length ? t.primarySoft : t.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: index <= pin.length ? t.primary : t.border,
                            width: index == pin.length ? 1.8 : 1,
                          ),
                        ),
                        child: Text(
                          index < pin.length ? pin[index] : '•',
                          style: TextStyle(
                            fontSize: AppFontSize.headline,
                            fontWeight: FontWeight.w800,
                            color: index < pin.length ? t.primary : t.muted,
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
                        fontSize: AppFontSize.bodyLarge,
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

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 21, color: t.ink),
        ),
      ),
    );
  }
}

class _HeaderPillButton extends StatelessWidget {
  const _HeaderPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: t.primary),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionPill extends StatelessWidget {
  const _InstructionPill();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: context.tokens.muted.withValues(alpha: .10),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.center_focus_strong_rounded, size: 16, color: t.primary),
          SizedBox(width: 8),
          Text(
            'QR kodu çerçeveye hizalayın',
            style: TextStyle(
              fontSize: AppFontSize.label,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridBackgroundPainter extends CustomPainter {
  const _GridBackgroundPainter({required this.color, required this.glow});

  final Color color;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 24.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = .7;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [glow.withValues(alpha: .2), glow.withValues(alpha: 0)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .72, size.height * .66),
              radius: size.width * .65,
            ),
          );
    canvas.drawRect(Offset.zero & size, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _GridBackgroundPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glow != glow;
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
                  color: context.tokens.success.withValues(
                    alpha: (1.0 - _anim.value).clamp(0.0, 0.6),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: context.tokens.success,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
