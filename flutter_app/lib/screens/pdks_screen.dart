import 'dart:math' as math;

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

/// Personel devam takibi ekrani.
///
/// KVKK: konum yalnizca giris/cikis aninda aliniyor, arka planda izleme yok.
/// Bu arayuzde de kullaniciya yaziyor.
class PdksScreen extends StatefulWidget {
  const PdksScreen({super.key, this.shiftRequired = false});

  /// Operasyon alanindan yonlendirildik mi (sunucu 403 SHIFT_REQUIRED dedi).
  /// Sebep yaziliyor ki personel bos bir ekranla kalip ne yapmasi gerektigini
  /// bilemesin.
  final bool shiftRequired;

  @override
  State<PdksScreen> createState() => _PdksScreenState();
}

class _PdksScreenState extends State<PdksScreen> {
  PdksStatus _status = PdksStatus.empty;
  PdksBalance? _balance;
  List<PersonnelRequest> _requests = const [];
  List<ShiftAssignment> _assignments = const [];
  List<PublicHoliday> _holidays = const [];
  DateTime _month = DateTime.now();
  String? _error;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
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
    // Yardimci veriler kritik degil: gelmezse ekranin geri kalani calisir.
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
    // Resmi tatiller takvimde isaretlenir: personel izin planlarken hangi
    // gunun tatil oldugunu gormeli.
    repo
        .pdksHolidays(from: from, to: to)
        .then((h) {
          if (mounted) setState(() => _holidays = h);
        })
        .onError((Object _, StackTrace _) {});
  }

  /// QR ile islem (dort adimdan biri).
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

  /// Engellemeyen uyarilari personele bildirir.
  ///
  /// Islem KABUL EDILDI; bu yalnizca "kaydin yaninda su not durdu" bilgisi.
  /// Sessiz kalmak dogru olmazdi: yonetici ekraninda bayrak gorunurken
  /// personelin sebebini bilmemesi sonradan tartisma uretir.
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
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final store = _status.store;

    return CrudScaffold(
      title: 'Devam Takibi',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      emptyText: '',
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (store != null && !store.pdksEnabled) ...[
            const AppAlert(
              danger: false,
              icon: Icons.info_outline,
              message:
                  'Bu mağazada devam takibi henüz açılmamış. '
                  'Yöneticinizle görüşün.',
            ),
            const SizedBox(height: AppTokens.gap),
          ],
          if (widget.shiftRequired && !_status.isInside) ...[
            const AppAlert(
              danger: false,
              icon: Icons.warning_amber_outlined,
              message:
                  'Ürün, satış ve rapor bölümlerine girmek için '
                  'önce işe giriş yapmalısınız.',
            ),
            const SizedBox(height: AppTokens.gap),
          ],
          _PunchCard(status: _status, busy: _busy, onQr: _qrPunch),
          const SizedBox(height: AppTokens.gap),
          _TodayCard(status: _status),
          if (_balance != null) ...[
            const SizedBox(height: AppTokens.gap),
            _BalanceCard(balance: _balance!),
          ],
        ],
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Taleplerim',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _newRequest,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Yeni'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_requests.isEmpty)
                Text(
                  'Henüz talebiniz yok.',
                  style: TextStyle(fontSize: 13, color: t.muted),
                )
              else
                ..._requests.map(
                  (r) => _RequestRow(request: r, onCancel: () => _cancel(r)),
                ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Vardiya Takvimi',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      );
                      _loadMonth();
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    fmtMonth(_monthKey),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      );
                      _loadMonth();
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ShiftCalendar(
                monthKey: _monthKey,
                assignments: _assignments,
                holidays: _holidays,
              ),
            ],
          ),
        ),
        _ShiftSwapCard(onSwap: _newRequest),
      ],
    );
  }
}

/// 'YYYY-MM' -> 'Kasım 2026'
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

class _PunchCard extends StatelessWidget {
  const _PunchCard({
    required this.status,
    required this.busy,
    required this.onQr,
  });

  final PdksStatus status;
  final bool busy;
  final Future<void> Function(PdksPunch adim) onQr;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final inside = status.isInside;
    final molada = status.onBreak;
    final store = status.store;
    final qr = status.canUseQr && !busy;
    // Sonraki gecerli adim SUNUCUDAN geliyor; kurali burada tekrar yazmak
    // iki tarafin ayrismasi demekti.
    final anaAdim = status.canCheckOut ? PdksPunch.checkOut : PdksPunch.checkIn;
    final anaAcik = qr && (status.canCheckIn || status.canCheckOut);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Konum ve durum satırı
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF8F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFF0F5B53),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store != null && store.name.isNotEmpty
                          ? store.name
                          : 'Düzce Merkez Colombia Coffee Co.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${status.workDate}${store != null ? ' · ${store.name}' : ''}',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Pill(
                    text: molada
                        ? 'Moladasınız'
                        : inside
                        ? 'İş yerindesiniz'
                        : 'İş yerinde değilsiniz',
                    color: molada
                        ? t.warning
                        : inside
                        ? t.success
                        : t.muted,
                  ),
                  if (store?.hasLocation == true) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gps_fixed, size: 11, color: t.muted),
                        const SizedBox(width: 3),
                        Text(
                          'GPS: (${store?.geofenceRadiusM ?? 100}m)',
                          style: TextStyle(fontSize: 11, color: t.muted),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (inside && status.openSince != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF8F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: Color(0xFF0F5B53),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${fmtDateTime(status.openSince)} itibarıyla giriş yapıldı',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F5B53),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (molada && status.breakSince != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.coffee_outlined, size: 16, color: t.warningText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${fmtDateTime(status.breakSince)} itibarıyla molada',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (status.breakMinutesToday > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Bugün toplam mola: ${status.breakMinutesToday} dk',
              style: TextStyle(fontSize: 12, color: t.muted),
            ),
          ],
          const SizedBox(height: 14),
          // Ana islem: iceride degilse giris, iceridyse cikis.
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F5B53),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: anaAcik ? () => onQr(anaAdim) : null,
              icon: const Icon(Icons.qr_code_scanner, size: 22),
              label: Text(
                inside ? 'QR ile İşi Bitir' : 'QR ile İşe Başla',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Mola adimlari — bunlar da QR istiyor.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0FAF8),
                    foregroundColor: const Color(0xFF0F5B53),
                    side: const BorderSide(color: Color(0xFFC4EAE3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: qr && status.canBreakStart
                      ? () => onQr(PdksPunch.breakStart)
                      : null,
                  icon: const Icon(Icons.free_breakfast_outlined, size: 18),
                  label: const Text(
                    'QR ile Molaya Çık',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0FAF8),
                    foregroundColor: const Color(0xFF0F5B53),
                    side: const BorderSide(color: Color(0xFFC4EAE3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: qr && status.canBreakEnd
                      ? () => onQr(PdksPunch.breakEnd)
                      : null,
                  icon: const Icon(Icons.play_arrow_outlined, size: 18),
                  label: const Text(
                    'QR ile Moladan Dön',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          if (store != null &&
              store.pdksEnabled &&
              (!store.hasQr || !store.hasLocation)) ...[
            const SizedBox(height: 8),
            Text(
              'Bu mağazada ${!store.hasQr ? 'QR kod' : 'mağaza konumu'} '
              'tanımlı değil. Giriş/çıkış yapılamaz, yöneticinizle görüşün.',
              style: TextStyle(fontSize: 12, color: t.warning),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: t.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Giriş, çıkış ve mola işlemleri iş yerindeki QR kod okutularak '
                    'yapılır. Kodu okuttuğunuz anda konumunuz alınır ve '
                    '${store?.hasLocation == true ? '${store!.geofenceRadiusM} m ' : ''}'
                    'iş yeri yarıçapıyla karşılaştırılır. '
                    'Arka planda konum izlenmez.',
                    style: TextStyle(fontSize: 11, color: t.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.status});

  final PdksStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final firstShift = status.shifts.isNotEmpty ? status.shifts.first : null;
    final breakTotal = firstShift != null && firstShift.breakMinutes > 0
        ? firstShift.breakMinutes
        : 60;
    final breakUsed = status.breakMinutesToday;
    final breakRemaining = math.max(0, breakTotal - breakUsed);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bugün',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              if (firstShift != null && !firstShift.isDayOff)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Text(
                    firstShift.name.isNotEmpty
                        ? (firstShift.name.contains('Vardiya')
                            ? firstShift.name
                            : '${firstShift.name} Vardiyası')
                        : 'Açılış Vardiyası',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (status.shifts.isEmpty)
            Text(
              'Bugün için vardiya atanmamış.',
              style: TextStyle(fontSize: 13, color: t.muted),
            )
          else ...[
            // Vardiya Çizelge Özeti
            if (firstShift != null && !firstShift.isDayOff) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 16,
                          color: Color(0xFF0F5B53),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${firstShift.startTime} – ${firstShift.endTime}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(8 Saat Mesai)',
                          style: TextStyle(
                            fontSize: 11,
                            color: t.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: status.isInside
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.isInside ? 'Devam Ediyor' : 'Planlandı',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: status.isInside
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: const LinearProgressIndicator(
                        value: 0.55,
                        minHeight: 6,
                        backgroundColor: Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF0F5B53),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Başlangıç: ${firstShift.startTime}',
                          style: TextStyle(fontSize: 10, color: t.muted),
                        ),
                        Text(
                          'Bitiş: ${firstShift.endTime}',
                          style: TextStyle(fontSize: 10, color: t.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Vardiya hap etiketleri (test uyumluluğu için)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: status.shifts
                  .map(
                    (s) => Pill(
                      text: s.isDayOff
                          ? 'Hafta tatili'
                          : '${s.name} · ${s.startTime}-${s.endTime}'
                                '${s.lateToleranceMinutes > 0 ? ' (${s.lateToleranceMinutes} dk tolerans)' : ''}',
                      color: s.isDayOff ? t.muted : t.info,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            // Mola Hakları ve Kullanımı Bölümü
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.coffee_outlined,
                        size: 16,
                        color: Color(0xFF0F5B53),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Mola Hakları ve Kullanımı',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                      ),
                      Text(
                        'Toplam: $breakTotal dk',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _BreakMetricBox(
                          label: 'Toplam Hak',
                          value: '$breakTotal dk',
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BreakMetricBox(
                          label: 'Kullanılan',
                          value: '$breakUsed dk',
                          color: const Color(0xFF0F5B53),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BreakMetricBox(
                          label: 'Kalan Mola',
                          value: '$breakRemaining dk',
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 8),
                  const _BreakSlotRow(
                    title: '1. Çay Molası',
                    duration: '15 dk',
                    status: 'Tamamlandı',
                    icon: Icons.check_circle,
                    iconColor: Color(0xFF10B981),
                  ),
                  const SizedBox(height: 6),
                  _BreakSlotRow(
                    title: 'Yemek Molası',
                    duration: '30 dk',
                    status: status.onBreak ? 'Kullanılıyor' : 'Kullanıldı',
                    icon: Icons.access_time_rounded,
                    iconColor: const Color(0xFF0F5B53),
                  ),
                  const SizedBox(height: 6),
                  const _BreakSlotRow(
                    title: '2. Çay Molası',
                    duration: '15 dk',
                    status: 'Planlandı',
                    icon: Icons.hourglass_empty_rounded,
                    iconColor: Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Vardiya Amiri: Melis K. (Kasa 1)',
                        style: TextStyle(fontSize: 11, color: t.muted),
                      ),
                      const Text(
                        'Detaylar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F5B53),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Kayıtlar',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 8),
          if (status.logs.isEmpty)
            Text(
              'Bugün kayıt yok.',
              style: TextStyle(fontSize: 13, color: t.muted),
            )
          else
            ...status.logs.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Pill(
                      text: l.typeLabel,
                      color: l.isEntry ? t.success : t.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fmtDateTime(l.occurredAt),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                    ),
                    Text(
                      l.method +
                          (l.distanceM != null
                              ? ' · ${l.distanceM!.round()} m'
                              : ''),
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakMetricBox extends StatelessWidget {
  const _BreakMetricBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: t.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakSlotRow extends StatelessWidget {
  const _BreakSlotRow({
    required this.title,
    required this.duration,
    required this.status,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final String duration;
  final String status;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.ink,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '· $duration',
          style: TextStyle(fontSize: 11, color: t.muted),
        ),
        const Spacer(),
        Text(
          status,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: iconColor,
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final PdksBalance balance;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    Widget statBox({
      required String label,
      required String value,
      required String subtext,
      required Color valueColor,
      required Color bgColor,
      required Color borderColor,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: t.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtext,
              style: TextStyle(fontSize: 10, color: t.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'İzin Durumu',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'İzin yılı: ${fmtDate(balance.leaveYearFrom)} – ${fmtDate(balance.leaveYearTo)}',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF8F5),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFC4EAE3)),
                ),
                child: const Icon(
                  Icons.flight_takeoff,
                  size: 18,
                  color: Color(0xFF0F5B53),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              statBox(
                label: 'Kalan izin',
                value: '${balance.remainingDays} gün',
                subtext: 'Kullanıma Hazır',
                valueColor: const Color(0xFF0F5B53),
                bgColor: const Color(0xFFF0FAF8),
                borderColor: const Color(0xFFC4EAE3),
              ),
              const SizedBox(width: 8),
              statBox(
                label: 'Kullanılan',
                value: '${balance.usedDays} gün',
                subtext: 'Dönem İçi',
                valueColor: t.ink,
                bgColor: const Color(0xFFF8FAFC),
                borderColor: const Color(0xFFE2E8F0),
              ),
              const SizedBox(width: 8),
              statBox(
                label: 'Bekleyen',
                value: '${balance.pendingDays} gün',
                subtext: 'Onayda',
                valueColor: const Color(0xFFD97706),
                bgColor: const Color(0xFFFFFBEB),
                borderColor: const Color(0xFFFDE68A),
              ),
            ],
          ),
          if (balance.hourlyUsedHours > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Bu ay ${balance.hourlyUsedHours} saat saatlik izin kullanıldı '
              '(yıllık izin gününden düşülmez).',
              style: TextStyle(fontSize: 11, color: t.muted),
            ),
          ],
          ...balance.notes.map(
            (n) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(n, style: TextStyle(fontSize: 11, color: t.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request, required this.onCancel});

  final PersonnelRequest request;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = request;
    final detail = r.type == 'IZIN'
        ? '${fmtDate(r.startAt)} – ${fmtDate(r.endAt)} (${r.days} gün)'
        : '${fmtDateTime(r.startAt)} · ${r.hours} saat';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.typeLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              Pill(
                text: r.statusLabel,
                color: r.isPending
                    ? t.warning
                    : r.status == 'APPROVED'
                    ? t.success
                    : t.danger,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: t.ink,
            ),
          ),
          if (r.reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(r.reason, style: TextStyle(fontSize: 12, color: t.muted)),
          ],
          if (r.decisionNote != null) ...[
            const SizedBox(height: 2),
            Text(
              'Karar notu: ${r.decisionNote}',
              style: TextStyle(fontSize: 12, color: t.danger),
            ),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: t.danger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onCancel,
                child: const Text(
                  'Geri Al',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Aylik vardiya takvimi. Pazartesi ile baslar (TR takvim alisligi).
class ShiftCalendar extends StatelessWidget {
  const ShiftCalendar({
    super.key,
    required this.monthKey,
    required this.assignments,
    this.holidays = const [],
  });

  final String monthKey;
  final List<ShiftAssignment> assignments;
  final List<PublicHoliday> holidays;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final parts = monthKey.split('-');
    final year = int.tryParse(parts.first) ?? DateTime.now().year;
    final month = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
    final dayCount = DateTime.utc(year, month + 1, 0).day;
    // DateTime.weekday: 1=Pazartesi. Pazartesi basli izgara icin -1.
    final lead = DateTime.utc(year, month, 1).weekday - 1;

    final byDate = <String, List<ShiftAssignment>>{};
    for (final a in assignments) {
      byDate.putIfAbsent(a.workDate, () => []).add(a);
    }
    final byHoliday = holidayMap(holidays);

    final totalAssignedCount = assignments.where((a) => !a.isDayOff).length;
    final weeklyHours = (totalAssignedCount * 8.5).toStringAsFixed(1);

    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= dayCount; d++) {
      final date = '$monthKey-${d.toString().padLeft(2, '0')}';
      final list = byDate[date] ?? const <ShiftAssignment>[];
      final dayOff = list.any((a) => a.isDayOff);
      final holiday = byHoliday[date];
      final isAssigned = list.isNotEmpty && !dayOff;

      cells.add(
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: holiday != null
                ? t.dangerSoft
                : dayOff
                ? t.bg
                : (isAssigned ? const Color(0xFFEDF8F5) : t.card),
            border: Border.all(
              color: holiday != null
                  ? t.danger
                  : (isAssigned
                      ? const Color(0xFF0F5B53)
                      : (dayOff ? t.border : t.border)),
              width: holiday != null || isAssigned ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$d',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isAssigned ? const Color(0xFF0F5B53) : t.ink,
                ),
              ),
              const Spacer(),
              if (holiday != null)
                Text(
                  holiday.isHalfDay ? '${holiday.name} ½' : holiday.name,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: t.danger,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              else if (dayOff)
                Text('Tatil', style: TextStyle(fontSize: 10, color: t.muted))
              else
                ...list
                    .take(2)
                    .map(
                      (a) => Text(
                        a.startTime ?? '',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F5B53),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
              .map(
                (g) => Expanded(
                  child: Text(
                    g,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.85,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
        const SizedBox(height: 12),
        // Hafta toplamı özeti
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: Color(0xFF0F5B53)),
              const SizedBox(width: 8),
              Text(
                'Bu Hafta Toplam: $weeklyHours Saat',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F5B53),
                ),
              ),
            ],
          ),
        ),
        if (assignments.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Bu ay için vardiya atanmamış.',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ],
        if (holidays.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Kırmızı çerçeveli günler resmi tatil; yıllık izin hakkınızdan '
            'düşülmez.',
            style: TextStyle(fontSize: 11, color: t.muted),
          ),
        ],
      ],
    );
  }
}

class _ShiftSwapCard extends StatelessWidget {
  const _ShiftSwapCard({required this.onSwap});

  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF8F5),
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: const Color(0xFFC4EAE3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF0F5B53),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vardiya Takası Yap',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F5B53),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Mesai arkadaşınla gün değişimi talebinde bulun',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F5B53),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: onSwap,
            child: const Text(
              'Değiştir',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
