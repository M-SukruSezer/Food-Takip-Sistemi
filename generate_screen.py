import re

flutter_code = """
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/pdks_export.dart';
import '../core/repository.dart';
import '../core/new_theme.dart';
import '../models/pdks.dart';
import '../widgets/dialogs.dart';
import 'pdks_dialogs.dart';

class PdksAdminScreen extends StatefulWidget {
  const PdksAdminScreen({super.key});

  @override
  State<PdksAdminScreen> createState() => _PdksAdminScreenState();
}

enum _Tab { now, requests, timesheet, staff }

class _PdksAdminScreenState extends State<PdksAdminScreen> {
  _Tab _tab = _Tab.now;
  List<PdksProfile> _profiles = const [];
  bool _disa = false;

  PresenceSnapshot _presence = PresenceSnapshot.empty;
  List<PersonnelRequest> _requests = const [];
  TimesheetReport _sheet = TimesheetReport.empty;
  String _requestFilter = 'PENDING';
  int _pendingCount = 0;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  int? _expanded;
  String? _error;
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_tab == _Tab.now) _loadPresence();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _d(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}'
      '-${v.month.toString().padLeft(2, '0')}'
      '-${v.day.toString().padLeft(2, '0')}';

  Future<void> _load({bool silent = false}) async {
    try {
      await _loadPresence(silent: silent);
      if (!mounted) return;
      setState(() {
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
    _loadRequests();
    _loadSheet();
  }

  Future<void> _loadPresence({bool silent = true}) async {
    final p = await repo.pdksNow(silent: silent);
    if (mounted) setState(() => _presence = p);
  }

  void _loadRequests() {
    repo
        .pdksRequests(status: _requestFilter.isEmpty ? null : _requestFilter)
        .then((r) {
          if (mounted) setState(() => _requests = r);
        })
        .onError((Object _, StackTrace _) {});
    repo
        .pdksRequests(status: 'PENDING')
        .then((r) {
          if (mounted) setState(() => _pendingCount = r.length);
        })
        .onError((Object _, StackTrace _) {});
  }

  void _loadSheet() {
    repo
        .pdksTimesheet(from: _d(_from), to: _d(_to), silent: true)
        .then((s) {
          if (mounted) setState(() => _sheet = s);
        })
        .onError((Object _, StackTrace _) {});
  }

  Future<void> _approve(PersonnelRequest r) async {
    final ok = await confirmDialog(
      context,
      title: 'Talebi Onayla',
      danger: false,
      confirmLabel: 'Onayla',
      body: Text(
        '${r.fullName ?? ''} · ${r.typeLabel}\n'
        '${_detail(r)}\n\n${r.reason}',
      ),
    );
    if (ok != true) return;
    try {
      await repo.pdksDecideRequest(r.id, true);
    } catch (_) {}
    _loadRequests();
    _loadSheet();
  }

  Future<void> _reject(PersonnelRequest r) async {
    final ok = await showRequestRejectDialog(context, r);
    if (ok == true) {
      toastSaved('Talep reddedildi');
      _loadRequests();
    }
  }

  static String _detail(PersonnelRequest r) => r.type == 'IZIN'
      ? '${fmtDate(r.startAt)} – ${fmtDate(r.endAt)} (${r.days} gün)'
      : '${fmtDateTime(r.startAt)} · ${r.hours} saat';

  Future<void> _loadProfiles() async {
    try {
      final p = await repo.pdksProfiles();
      if (mounted) setState(() => _profiles = p);
    } catch (_) {}
  }

  Future<void> _excelAktar() async {
    setState(() => _disa = true);
    try {
      await exportTimesheetExcel(_sheet);
    } catch (e) {
      toast('Dışa aktarılamadı', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _disa = false);
    }
  }

  Future<void> _pdfAktar() async {
    setState(() => _disa = true);
    try {
      await exportTimesheetPdf(_sheet);
    } catch (e) {
      toast('Dışa aktarılamadı', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _disa = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NewTokens.surface,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(top: 80, bottom: 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildModeSwitcher(),
                    _buildStatusBanner(),
                    _buildActionCard(),
                    _buildShiftDetail(),
                    _buildLeaveStatus(),
                    _buildRequests(),
                    _buildCalendar(),
                    _buildBottomAction(),
                  ]),
                ),
              ),
            ],
          ),
          _buildHeader(),
          _buildFab(),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: NewTokens.surface.withOpacity(0.85),
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Container(
              height: 80,
              padding: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    offset: Offset(0, 1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: NewTokens.tertiaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Düzce Merkez Şube'.toUpperCase(),
                                      style: NewTokens.labelSm.copyWith(
                                        color: NewTokens.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Ana Sayfa',
                                style: NewTokens.headlineSm.copyWith(
                                  color: NewTokens.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Muhammed Ş. Sezer · Mağaza Müdürü',
                                style: NewTokens.labelSm.copyWith(
                                  color: NewTokens.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(Icons.notifications, color: NewTokens.onSurfaceVariant),
                            onPressed: () {},
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: NewTokens.error,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '7',
                                style: NewTokens.labelSm.copyWith(
                                  color: NewTokens.onError,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.power_settings_new, color: NewTokens.onSurfaceVariant),
                        onPressed: () {},
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        margin: EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: NewTokens.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.person, color: NewTokens.onPrimary, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.badge, size: 18, color: NewTokens.primary),
                    SizedBox(width: 6),
                    Text('PDKS & Devam', style: NewTokens.labelMd.copyWith(color: NewTokens.primary)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.storefront, size: 18, color: NewTokens.onSurfaceVariant),
                    SizedBox(width: 6),
                    Text('Operasyon', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, color: NewTokens.primary, size: 20),
                    SizedBox(width: 4),
                    Text('Düzce Merkez Colombia', style: NewTokens.labelLg.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: NewTokens.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: NewTokens.primary, shape: BoxShape.circle)),
                      SizedBox(width: 6),
                      Text('İş yerindesiniz', style: NewTokens.labelSm.copyWith(color: NewTokens.onSecondaryContainer)),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('27 Eylül 2026, Pazar', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                Row(
                  children: [
                    Icon(Icons.my_location, size: 14, color: NewTokens.primary),
                    SizedBox(width: 4),
                    Text('GPS: Şube sınırları içi (12m)', style: NewTokens.labelSm.copyWith(color: NewTokens.primary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.qr_code_scanner, color: NewTokens.primary, size: 20),
                    ),
                    SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hızlı Devam Kaydı', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface)),
                        Text('Karekod okutarak durum güncelle', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NewTokens.surfaceContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Aktif Terminal', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                ),
              ],
            ),
            SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: NewTokens.primary,
                foregroundColor: NewTokens.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: Size.fromHeight(48),
              ),
              onPressed: () {},
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, size: 22),
                  SizedBox(width: 8),
                  Text('QR ile İşe Başla', style: NewTokens.headlineSm.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NewTokens.surfaceContainerLow,
                      foregroundColor: NewTokens.onSurface,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: Size.fromHeight(44),
                    ),
                    onPressed: () {},
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_cafe, size: 18, color: NewTokens.secondary),
                        SizedBox(width: 6),
                        Text('QR ile Molaya Çık', style: NewTokens.labelLg),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NewTokens.surfaceContainerLow,
                      foregroundColor: NewTokens.onSurface,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: Size.fromHeight(44),
                    ),
                    onPressed: () {},
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_circle, size: 18, color: NewTokens.primary),
                        SizedBox(width: 6),
                        Text('QR ile Moladan Dön', style: NewTokens.labelLg),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info, color: NewTokens.onSurfaceVariant, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Giriş, çıkış ve mola işlemleri kasadaki kiosk QR kodunu okutarak yapılır. Konum doğrulaması 100m yarıçapında geçerlidir; arka planda konum izlenmez.',
                      style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftDetail() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bugünün Çizelgesi', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface)),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: NewTokens.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('Açılış Vardiyası', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurface)),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Planlanan Saat', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                        SizedBox(height: 2),
                        Text('08:30 – 17:00', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: NewTokens.tertiary, shape: BoxShape.circle)),
                            SizedBox(width: 4),
                            Text('8.5 Saat Görev', style: NewTokens.labelSm.copyWith(color: NewTokens.tertiary, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kullanılan Mola', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                        SizedBox(height: 2),
                        Text('15 / 45 dk', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: 15 / 45,
                          backgroundColor: NewTokens.surfaceContainer,
                          color: NewTokens.primary,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, size: 18, color: NewTokens.onSurfaceVariant),
                    SizedBox(width: 8),
                    Text('Vardiya Amiri: Melis K. (Kasa 1)', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
                Text('Detaylar', style: NewTokens.labelSm.copyWith(color: NewTokens.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveStatus() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('İzin Durumu', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface)),
                    Text('İzin yılı: 14.06.2026 – 13.06.2027', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: NewTokens.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.flight_takeoff, size: 16, color: NewTokens.onSecondaryContainer),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text('Kalan İzin', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                        SizedBox(height: 2),
                        Text('7 Gün', style: NewTokens.numericMetric.copyWith(color: NewTokens.primary, fontSize: 20)),
                        Text('Kullanıma Hazır', style: NewTokens.labelSm.copyWith(color: NewTokens.primary, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text('Kullanılan', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                        SizedBox(height: 2),
                        Text('0 Gün', style: NewTokens.numericMetric.copyWith(color: NewTokens.onSurface, fontSize: 20)),
                        Text('Dönem içi', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text('Bekleyen', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                        SizedBox(height: 2),
                        Text('${_pendingCount} Talep', style: NewTokens.numericMetric.copyWith(color: NewTokens.secondary, fontSize: 20)),
                        Text('Onayda', style: NewTokens.labelSm.copyWith(color: NewTokens.secondary, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Yıllık izin hesabında hafta tatilleri düşülür; arife gibi yarım tatiller 0,5 gün sayılır. Dini ve resmi bayram günleri takvime sistemce otomatik yansıtılır.',
              style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequests() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Taleplerim', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface)),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: NewTokens.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 16, color: NewTokens.onPrimary),
                      SizedBox(width: 4),
                      Text('Yeni İzin', style: NewTokens.labelMd.copyWith(color: NewTokens.onPrimary)),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            ..._requests.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: NewTokens.secondary, shape: BoxShape.circle)),
                            SizedBox(width: 8),
                            Text(r.fullName ?? 'Yıllık İzin', style: NewTokens.labelLg.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                            SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: NewTokens.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(r.statusLabel, style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 11)),
                            ),
                          ],
                        ),
                        if (r.isPending)
                          InkWell(
                            onTap: () => _reject(r),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: NewTokens.errorContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('İptal', style: NewTokens.labelSm.copyWith(color: NewTokens.onErrorContainer)),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(_detail(r), style: NewTokens.bodyMd.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.w500)),
                    Text('Açıklama: ${r.reason}', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Vardiya Takvimi', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface)),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.chevron_left, size: 18, color: NewTokens.onSurfaceVariant),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Eylül 2026', style: NewTokens.headlineSm.copyWith(fontSize: 15, fontWeight: FontWeight.bold, color: NewTokens.onSurface)),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.chevron_right, size: 18, color: NewTokens.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'].map((d) => Expanded(
                child: Center(child: Text(d, style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant))),
              )).toList(),
            ),
            SizedBox(height: 8),
            // Dummy grid just to match HTML design look
            GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.8,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 35,
              itemBuilder: (ctx, i) {
                if (i < 5) return SizedBox();
                int day = i - 4;
                bool isToday = day == 27;
                bool isActive = day >= 21 && day <= 26;
                return Container(
                  decoration: BoxDecoration(
                    color: isToday ? NewTokens.primary : isActive ? NewTokens.surfaceContainerHigh : NewTokens.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$day', style: NewTokens.labelSm.copyWith(
                        color: isToday ? NewTokens.onPrimary : NewTokens.onSurface,
                        fontWeight: isToday ? FontWeight.w900 : FontWeight.bold,
                      )),
                      Text(
                        isToday ? 'Tatil' : isActive ? '16:00' : (day > 27 ? 'Tatil' : ''),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isToday ? NewTokens.onPrimary : isActive ? NewTokens.primary : NewTokens.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timelapse, color: NewTokens.primary, size: 18),
                      SizedBox(width: 6),
                      Text('Bu Hafta Toplam:', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface)),
                    ],
                  ),
                  Text('42.5 Saat', style: NewTokens.headlineSm.copyWith(color: NewTokens.primary, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: NewTokens.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.swap_horiz, color: NewTokens.onSecondaryContainer, size: 20),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vardiya Takası Yap', style: NewTokens.labelLg.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                    Text('Mesai arkadaşınla gün değişimi talep et', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('Değiştir', style: NewTokens.labelMd.copyWith(color: NewTokens.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Positioned(
      bottom: 80,
      right: 16,
      child: FloatingActionButton(
        backgroundColor: NewTokens.primary,
        foregroundColor: NewTokens.onPrimary,
        child: Icon(Icons.barcode_reader, size: 28),
        onPressed: () {},
      ),
    );
  }

  Widget _buildBottomNav() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 64,
            color: NewTokens.surface.withOpacity(0.9),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  offset: Offset(0, -2),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.dashboard, 'Ana Sayfa', true),
                _buildNavItem(Icons.inventory_2, 'Ürünler', false),
                _buildNavItem(Icons.timer, 'Öneri / SKT', false, badge: '72'),
                _buildNavItem(Icons.monitoring, 'Rapor', false),
                _buildNavItem(Icons.widgets, 'Menü', false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, {String? badge}) {
    return Expanded(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isActive ? NewTokens.primary : NewTokens.onSurfaceVariant, size: 22),
              SizedBox(height: 2),
              Text(
                label,
                style: NewTokens.labelSm.copyWith(
                  color: isActive ? NewTokens.primary : NewTokens.onSurfaceVariant,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          if (badge != null)
            Positioned(
              top: 8,
              right: 16,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: NewTokens.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: NewTokens.labelSm.copyWith(color: NewTokens.onError, fontSize: 9),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
"""

with open('/home/msukrusezer/Belgeler/Default Project/flutter_app/lib/screens/pdks_admin_screen.dart', 'w') as f:
    f.write(flutter_code)

print("done")
