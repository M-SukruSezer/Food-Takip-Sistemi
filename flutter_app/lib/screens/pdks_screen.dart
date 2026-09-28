import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/device_integrity.dart';
import '../core/pdks_location.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/pdks.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';
import 'pdks_dialogs.dart';
import 'qr_scan_screen.dart';
import '../core/new_theme.dart';

class PdksScreen extends StatefulWidget {
  const PdksScreen({super.key, this.shiftRequired = false});

  final bool shiftRequired;

  @override
  State<PdksScreen> createState() => _PdksScreenState();
}

class _PdksScreenState extends State<PdksScreen>
    with SingleTickerProviderStateMixin {
  PdksStatus _status = PdksStatus.empty;
  PdksBalance? _balance;
  List<PersonnelRequest> _requests = const [];
  List<ShiftAssignment> _assignments = const [];
  List<PublicHoliday> _holidays = const [];
  final DateTime _month = DateTime.now();
  String? _error;
  bool _loaded = false;
  bool _busy = false;

  late AnimationController _laserController;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _laserController.dispose();
    super.dispose();
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  Future<void> _load({bool silent = false}) async {
    try {
      final status = await repo.pdksStatus(silent: silent);
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loaded = true;
      });
      return;
    }
    repo
        .pdksBalance()
        .then((b) {
          if (mounted) setState(() => _balance = b);
        })
        .onError((Object _, StackTrace _) {});
    repo
        .pdksRequests()
        .then((r) {
          if (mounted) setState(() => _requests = r);
        })
        .onError((Object _, StackTrace _) {});
    _loadMonth();
  }

  void _loadMonth() {
    final last = DateTime.utc(_month.year, _month.month + 1, 0);
    final from = '$_monthKey-01';
    final to = '$_monthKey-${last.day.toString().padLeft(2, '0')}';
    repo
        .pdksAssignments(from: from, to: to)
        .then((a) {
          if (mounted) setState(() => _assignments = a);
        })
        .onError((Object _, StackTrace _) {});
    repo
        .pdksHolidays(from: from, to: to)
        .then((h) {
          if (mounted) setState(() => _holidays = h);
        })
        .onError((Object _, StackTrace _) {});
  }

  Future<void> _qrPunch(PdksPunch adim) async {
    final basliklar = {
      PdksPunch.checkIn: 'QR ile Giriş',
      PdksPunch.checkOut: 'QR ile Çıkış',
      PdksPunch.breakStart: 'QR ile Mola Başlangıcı',
      PdksPunch.breakEnd: 'QR ile Mola Bitişi',
    };
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScanScreen(title: basliklar[adim] ?? 'QR Okut'),
      ),
    );
    if (token == null || !mounted) return;

    setState(() => _busy = true);
    try {
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
        isMocked: pos.isMocked,
        integrity: integrity,
      );
      toastSaved(adim.mesaj);
      _warnIntegrity(integrity);
      await _load(silent: true);
    } on LocationDenied catch (e) {
      toast(e.message, kind: ToastKind.error);
    } catch (e) {
      toast(errorMessage(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _warnIntegrity(DeviceIntegrity integrity) {
    final w = integrity.warnings;
    if (w.isEmpty || !mounted) return;
    toast(
      'Kayıt alındı, not düşüldü: ${w.join(', ')}',
      kind: ToastKind.warning,
    );
  }

  Future<void> _newRequest() async {
    final ok = await showRequestDialog(context, balance: _balance);
    if (ok == true) await _load(silent: true);
  }

  Future<void> _cancel(PersonnelRequest r) async {
    final ok = await confirmDialog(
      context,
      title: 'Talebi Geri Al',
      confirmLabel: 'Geri Al',
      body: Text('${r.typeLabel} talebiniz geri alınacak.'),
    );
    if (ok != true) return;
    try {
      await repo.pdksCancelRequest(r.id);
    } catch (_) {}
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = _status.store;

    return Scaffold(
      backgroundColor: const Color(0xFF171717), // neutral-900
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A), // slate-900
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildSubHeader(),
              Expanded(
                child: _buildScannerView(store?.name ?? 'Bilinmeyen Mağaza'),
              ),
              _buildBottomNav(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: NewTokens.surfaceContainerLowest, // white
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'P',
                style: NewTokens.headlineSm.copyWith(
                  color: NewTokens.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '...',
                style: NewTokens.headlineSm.copyWith(
                  color: NewTokens.primaryContainer,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.only(
              left: 4,
              right: 14,
              top: 4,
              bottom: 4,
            ),
            decoration: BoxDecoration(
              color: NewTokens.surfaceBright,
              border: Border.all(
                color: NewTokens.outlineVariant.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [NewTokens.tertiary, NewTokens.primary],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: NewTokens.primaryContainer),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'MŞ',
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MUHAMMED ŞÜKRÜ SEZER',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurface,
                      ),
                    ),
                    Text(
                      'Store Manager',
                      style: NewTokens.bodySm.copyWith(
                        fontSize: 9,
                        color: NewTokens.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              Stack(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.notifications_none,
                      color: NewTokens.outline,
                      size: 20,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: NewTokens.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: NewTokens.onError, width: 1),
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: NewTokens.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NewTokens.errorContainer),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {},
                  icon: const Icon(
                    Icons.logout,
                    color: NewTokens.error,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubHeader() {
    return Container(
      color: NewTokens.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: NewTokens.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back,
                  color: NewTokens.onSurface,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'QR ile Giriş',
                style: NewTokens.bodyLg.copyWith(
                  fontWeight: FontWeight.bold,
                  color: NewTokens.onSurface,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: NewTokens.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.pin_outlined,
              color: NewTokens.onSurfaceVariant,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerView(String storeName) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0xFF0F172A), Color(0xFF0A0A0A), Colors.black],
                radius: 1.2,
              ),
            ),
          ),
          Positioned(
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: NewTokens.primary.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: NewTokens.primaryFixed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$storeName 📍',
                    style: NewTokens.labelMd.copyWith(
                      color: NewTokens.primaryFixed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 256,
                height: 256,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: NewTokens.primaryFixed.withValues(alpha: 0.9),
                    width: 2,
                  ),
                  color: NewTokens.primary.withValues(alpha: 0.05),
                ),
                child: Stack(
                  children: [
                    // Corners
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _buildCorner(top: true, left: true),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _buildCorner(top: true, left: false),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: _buildCorner(top: false, left: true),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: _buildCorner(top: false, left: false),
                    ),

                    // Laser
                    AnimatedBuilder(
                      animation: _laserController,
                      builder: (context, child) {
                        return Positioned(
                          top: 240 * _laserController.value + 8,
                          left: 12,
                          right: 12,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  NewTokens.primaryFixed,
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: NewTokens.primaryFixed.withValues(
                                    alpha: 0.8,
                                  ),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Crosshair
                    Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: NewTokens.primaryFixed.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: NewTokens.primaryFixed.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCameraButton(Icons.flash_on, 'Flaş Aç', Colors.amber),
                  const SizedBox(width: 16),
                  _buildCameraButton(Icons.pin, 'PIN Girişi', Colors.white),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            child: Column(
              children: [
                Text(
                  'QR kodu çerçeveye alın.',
                  style: NewTokens.bodyMd.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Kamera görüntüsü cihazdan çıkmıyor, sunucuya gönderilmiyor.',
                  style: NewTokens.bodySm.copyWith(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner({required bool top, required bool left}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        border: Border(
          top: top
              ? const BorderSide(color: NewTokens.primaryFixed, width: 4)
              : BorderSide.none,
          bottom: !top
              ? const BorderSide(color: NewTokens.primaryFixed, width: 4)
              : BorderSide.none,
          left: left
              ? const BorderSide(color: NewTokens.primaryFixed, width: 4)
              : BorderSide.none,
          right: !left
              ? const BorderSide(color: NewTokens.primaryFixed, width: 4)
              : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: top && left ? const Radius.circular(12) : Radius.zero,
          topRight: top && !left ? const Radius.circular(12) : Radius.zero,
          bottomLeft: !top && left ? const Radius.circular(12) : Radius.zero,
          bottomRight: !top && !left ? const Radius.circular(12) : Radius.zero,
        ),
      ),
    );
  }

  Widget _buildCameraButton(IconData icon, String label, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 14),
          const SizedBox(width: 8),
          Text(label, style: NewTokens.labelMd.copyWith(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      color: NewTokens.surfaceContainerLowest,
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.access_time, 'Devam', true),
          _buildNavItem(Icons.calendar_view_week, 'Çizelge', false),
          _buildNavItem(Icons.check_box_outlined, 'Yönetim', false),
          _buildNavItem(Icons.menu, 'Menü', false),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 28,
          decoration: BoxDecoration(
            color: isActive
                ? NewTokens.surfaceContainerLow
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: isActive ? NewTokens.primary : NewTokens.outline,
            size: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: NewTokens.labelSm.copyWith(
            color: isActive ? NewTokens.primary : NewTokens.outline,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

String fmtMonth(String key) {
  const names = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  final parts = key.split('-');
  if (parts.length != 2) return key;
  final m = int.tryParse(parts[1]);
  if (m == null || m < 1 || m > 12) return key;
  return '${names[m - 1]} ${parts[0]}';
}
