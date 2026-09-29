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
      backgroundColor: const Color(0xFFF8FBFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
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
              padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
              child: Row(
                children: [
                  _HeaderCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 11),
                  const Text(
                    'QR ile Giriş',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.35,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9FBF6),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFF9DE8D7)),
                    ),
                    child: const Text(
                      'PDKS',
                      style: TextStyle(
                        color: Color(0xFF00796B),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
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
      bottomNavigationBar: _typing ? null : const _QrBottomBar(),
    );
  }

  Widget _camera(AppTokens t) {
    final storeName = session.user?.storeName ?? 'Düzce Merkez Colombia Coffee';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF4FFFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF78E4D0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: Color(0xFF007D70),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    storeName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                const _PulsingDot(),
                const SizedBox(width: 6),
                const Text(
                  'CANLI (8m)',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF006F63),
                    letterSpacing: .3,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: CustomPaint(
            painter: const _GridBackgroundPainter(),
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFF8ACFC7),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF19B9A5)
                                        .withValues(alpha: .15),
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
                                    color: const Color(0xFFF8FBFC),
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.no_photography_outlined,
                                          color: Color(0xFF64748B),
                                          size: 34,
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          'Kamera kullanılamıyor',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF334155),
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
                            Positioned(
                              bottom: -58,
                              child: _CameraControls(
                                controller: _controller,
                                onPin: () => setState(() => _typing = true),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 22,
                      right: 22,
                      bottom: 20,
                      child: _PrivacyCard(),
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

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF3F7FA),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, size: 21, color: const Color(0xFF334155)),
      ),
    ),
  );
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
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF3F7FA),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE1E8EF)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF007D70)),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InstructionPill extends StatelessWidget {
  const _InstructionPill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A64748B),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.center_focus_strong_rounded,
          size: 16,
          color: Color(0xFF008C7D),
        ),
        SizedBox(width: 8),
        Text(
          'QR kodu çerçeveye hizalayın',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF27364A),
          ),
        ),
      ],
    ),
  );
}

class _CameraControls extends StatelessWidget {
  const _CameraControls({required this.controller, required this.onPin});

  final MobileScannerController controller;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F475569),
          blurRadius: 12,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<MobileScannerState>(
          valueListenable: controller,
          builder: (context, state, _) => _MiniControl(
            icon: Icons.flashlight_on_outlined,
            iconColor: const Color(0xFFF59E0B),
            label: 'Flaş',
            onTap: controller.toggleTorch,
          ),
        ),
        const _ControlDivider(),
        _MiniControl(
          icon: Icons.cameraswitch_outlined,
          label: 'Çevir',
          onTap: controller.switchCamera,
        ),
        const _ControlDivider(),
        _MiniControl(
          icon: Icons.pin_outlined,
          iconColor: const Color(0xFF008C7D),
          label: 'PIN',
          onTap: onPin,
        ),
      ],
    ),
  );
}

class _ControlDivider extends StatelessWidget {
  const _ControlDivider();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 11),
    color: const Color(0xFFE2E8F0),
  );
}

class _MiniControl extends StatelessWidget {
  const _MiniControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = const Color(0xFF52627A),
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFDDE6EC)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1464748B),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.verified_user_outlined,
              size: 17,
              color: Color(0xFF008C7D),
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'KVKK & Veri Güvenliği',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1FFFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF7BE2D0)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 13,
                    color: Color(0xFF008C7D),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Yenilenme: 24s',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF00796B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        const Text(
          'Görüntü yerel işlenir, sunucuya kaydedilmez. Konum doğrulandı (Hassasiyet: 8m).',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.4,
            color: Color(0xFF53647B),
          ),
        ),
      ],
    ),
  );
}

class _QrBottomBar extends StatelessWidget {
  const _QrBottomBar();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      height: 76,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5EDF2))),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomItem(icon: Icons.schedule_rounded, label: 'Devam'),
          _BottomItem(icon: Icons.calendar_month_outlined, label: 'Çizelge'),
          _BottomItem(
            icon: Icons.qr_code_scanner_rounded,
            label: 'QR Okut',
            active: true,
          ),
          _BottomItem(icon: Icons.checklist_rounded, label: 'Yönetim'),
          _BottomItem(icon: Icons.menu_rounded, label: 'Menü'),
        ],
      ),
    ),
  );
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 62,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform.translate(
          offset: Offset(0, active ? -11 : 0),
          child: Container(
            width: active ? 46 : 30,
            height: active ? 46 : 30,
            decoration: active
                ? const BoxDecoration(
                    color: Color(0xFF00897B),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x3D00796B),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  )
                : null,
            child: Icon(
              icon,
              size: active ? 24 : 20,
              color: active ? Colors.white : const Color(0xFF71839C),
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(0, active ? -8 : 0),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: active ? const Color(0xFF006E64) : const Color(0xFF586A83),
            ),
          ),
        ),
      ],
    ),
  );
}

class _GridBackgroundPainter extends CustomPainter {
  const _GridBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 24.0;
    final paint = Paint()
      ..color = const Color(0xFFDDECEF).withValues(alpha: .56)
      ..strokeWidth = .7;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final glow = Paint()
      ..shader =
          const RadialGradient(colors: [Color(0x337DE4D4), Color(0x007DE4D4)])
              .createShader(
                Rect.fromCircle(
                  center: Offset(size.width * .72, size.height * .66),
                  radius: size.width * .65,
                ),
              );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
