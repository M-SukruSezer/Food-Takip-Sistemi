import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/pdks.dart';
import '../widgets/panels.dart';

/// PIN Doğrulama: QR okutamayan partnerin gireceği 6 haneli kod.
///
/// Kod sunucuda mağaza sırrından üretilir ve 60 saniyede bir değişir; sayaç
/// bitince ekran yeni kodu kendiliğinden çeker. Partner kodu QR ekranındaki
/// "PIN ile Giriş" alanına yazar; konum ve cihaz kontrolleri QR'daki gibi
/// aynen uygulanır.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  RotatingPin? _pin;
  String? _error;
  int _left = 0;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _pin == null) return;
    if (_left <= 1) {
      _fetch();
      return;
    }
    setState(() => _left--);
  }

  Future<void> _fetch() async {
    if (_loading) return;
    _loading = true;
    try {
      final p = await repo.pdksCurrentPin();
      if (!mounted) return;
      setState(() {
        _pin = p;
        _left = p.expiresIn;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _left = 0;
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pin = _pin;
    final total = pin?.windowSeconds ?? 60;

    return ListView(
      padding: const EdgeInsets.all(AppTokens.gap),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AppCard(
              child: Column(
                children: [
                  Icon(Icons.pin_outlined, size: 36, color: t.primary),
                  const SizedBox(height: 8),
                  Text(
                    'PIN Doğrulama',
                    style: TextStyle(
                      fontSize: AppFontSize.title,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                    ),
                  ),
                  if (pin?.storeName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      pin!.storeName!,
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        color: t.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_error != null)
                    AppAlert(message: _error!)
                  else if (pin == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${pin.pin.substring(0, 3)} ${pin.pin.substring(3)}',
                        key: const ValueKey('pin-code'),
                        style: TextStyle(
                          fontSize: AppFontSize.hero,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 6,
                          color: t.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: LinearProgressIndicator(
                        value: (_left / total).clamp(0.0, 1.0),
                        minHeight: 8,
                        color: _left <= 10 ? t.warning : t.primary,
                        backgroundColor: t.border,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_left sn sonra yenilenir',
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.w600,
                        color: _left <= 10 ? t.warning : t.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'QR okutamayan partner, QR ekranında "PIN ile Giriş"i '
                    'seçip bu kodu girer. Kod 60 saniye geçerlidir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: t.muted,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _fetch,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tekrar Dene'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
