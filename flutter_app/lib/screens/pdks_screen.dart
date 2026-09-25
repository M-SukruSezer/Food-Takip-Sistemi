import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
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
  const PdksScreen({super.key});

  @override
  State<PdksScreen> createState() => _PdksScreenState();
}

class _PdksScreenState extends State<PdksScreen> {
  PdksStatus _status = PdksStatus.empty;
  PdksBalance? _balance;
  List<PersonnelRequest> _requests = const [];
  List<ShiftAssignment> _assignments = const [];
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
    repo.pdksBalance().then((b) {
      if (mounted) setState(() => _balance = b);
    }).onError((Object _, StackTrace _) {});
    repo.pdksRequests().then((r) {
      if (mounted) setState(() => _requests = r);
    }).onError((Object _, StackTrace _) {});
    _loadMonth();
  }

  void _loadMonth() {
    final last = DateTime.utc(_month.year, _month.month + 1, 0);
    repo.pdksAssignments(
      from: '$_monthKey-01',
      to: '$_monthKey-${last.day.toString().padLeft(2, '0')}',
    ).then((a) {
      if (mounted) setState(() => _assignments = a);
    }).onError((Object _, StackTrace _) {});
  }

  /// Konumla giris/cikis.
  Future<void> _gpsPunch(bool entry) async {
    setState(() => _busy = true);
    try {
      final pos = await currentPosition();
      await repo.pdksPunchGps(
        entry: entry,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        isMocked: pos.isMocked,
      );
      toastSaved(entry ? 'Giriş kaydedildi' : 'Çıkış kaydedildi');
      await _load(silent: true);
    } on LocationDenied catch (e) {
      toast(e.message, kind: ToastKind.error);
    } catch (e) {
      toast(errorMessage(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// QR ile giris/cikis.
  Future<void> _qrPunch(bool entry) async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScanScreen(title: entry ? 'QR ile Giriş' : 'QR ile Çıkış'),
      ),
    );
    if (token == null || !mounted) return;

    setState(() => _busy = true);
    try {
      // Sabit basili kod konum da istiyor. Konum alinabiliyorsa gonderilir;
      // alinamazsa donen kod tek basina yeterli olabilir.
      PdksPosition? pos;
      try {
        pos = await currentPosition();
      } catch (_) {
        pos = null;
      }
      await repo.pdksPunchQr(
        entry: entry,
        token: token,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
        accuracy: pos?.accuracy,
        isMocked: pos?.isMocked,
      );
      toastSaved(entry ? 'Giriş kaydedildi' : 'Çıkış kaydedildi');
      await _load(silent: true);
    } catch (e) {
      toast(errorMessage(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showMyQr() async {
    try {
      final token = await repo.pdksMyQr();
      if (!mounted) return;
      await showQrDialog(
        context,
        title: 'Kodumu Göster',
        token: token,
        onRefresh: repo.pdksMyQr,
        note: 'Kiosk bu kodu okutacak. Kod '
            '${token.windowSeconds} saniyede bir yenilenir.',
      );
    } catch (e) {
      toast(errorMessage(e), kind: ToastKind.error);
    }
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
              message: 'Bu mağazada devam takibi henüz açılmamış. '
                  'Yöneticinizle görüşün.',
            ),
            const SizedBox(height: AppTokens.gap),
          ],
          _PunchCard(
            status: _status,
            busy: _busy,
            onGps: _gpsPunch,
            onQr: _qrPunch,
            onMyQr: _showMyQr,
          ),
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
                    child: Text('Taleplerim',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
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
                Text('Henüz talebiniz yok.',
                    style: TextStyle(fontSize: 13, color: t.muted))
              else
                ..._requests.map((r) => _RequestRow(request: r, onCancel: () => _cancel(r))),
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
                    child: Text('Vardiya Takvimi',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _month = DateTime(_month.year, _month.month - 1));
                      _loadMonth();
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(fmtMonth(_monthKey),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
                  IconButton(
                    onPressed: () {
                      setState(() => _month = DateTime(_month.year, _month.month + 1));
                      _loadMonth();
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ShiftCalendar(monthKey: _monthKey, assignments: _assignments),
            ],
          ),
        ),
      ],
    );
  }
}

/// 'YYYY-MM' -> 'Kasım 2026'
String fmtMonth(String key) {
  const names = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
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
    required this.onGps,
    required this.onQr,
    required this.onMyQr,
  });

  final PdksStatus status;
  final bool busy;
  final Future<void> Function(bool entry) onGps;
  final Future<void> Function(bool entry) onQr;
  final Future<void> Function() onMyQr;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final inside = status.isInside;
    final store = status.store;
    final gps = status.canUseGps && !busy;
    final qr = status.canUseQr && !busy;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${status.workDate}${store != null ? ' · ${store.name}' : ''}',
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
              ),
              Pill(
                text: inside ? 'İş yerindesiniz' : 'İş yerinde değilsiniz',
                color: inside ? t.success : t.muted,
              ),
            ],
          ),
          if (inside && status.openSince != null) ...[
            const SizedBox(height: 6),
            Text('${fmtDateTime(status.openSince)} itibarıyla giriş yapıldı',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.success)),
          ],
          const SizedBox(height: 14),
          // Ana islem: iceride degilse giris, iceridyse cikis.
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: gps && (inside ? true : true)
                  ? () => onGps(!inside)
                  : null,
              icon: Icon(inside ? Icons.logout : Icons.login),
              label: Text(inside ? 'Konumla İşi Bitir' : 'Konumla İşe Başla'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: qr ? () => onQr(!inside) : null,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text('QR Okut (${inside ? 'çıkış' : 'giriş'})'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: qr ? () => onMyQr() : null,
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('Kodumu Göster'),
                ),
              ),
            ],
          ),
          if (store != null && store.pdksEnabled && !store.hasLocation) ...[
            const SizedBox(height: 8),
            Text(
              'Mağaza konumu tanımlanmadığı için konumla giriş kapalı. '
              'QR ile giriş yapabilirsiniz.',
              style: TextStyle(fontSize: 12, color: t.warning),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_outlined, size: 14, color: t.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Konumunuz yalnızca giriş/çıkış anında alınır ve '
                  '${store?.hasLocation == true ? '${store!.geofenceRadiusM} m ' : ''}'
                  'iş yeri yarıçapıyla karşılaştırılır. '
                  'Arka planda konum izlenmez.',
                  style: TextStyle(fontSize: 11, color: t.muted),
                ),
              ),
            ],
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bugün',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 8),
          if (status.shifts.isEmpty)
            Text('Bugün için vardiya atanmamış.',
                style: TextStyle(fontSize: 13, color: t.muted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: status.shifts
                  .map((s) => Pill(
                        text: s.isDayOff
                            ? 'Hafta tatili'
                            : '${s.name} · ${s.startTime}-${s.endTime}'
                                '${s.lateToleranceMinutes > 0 ? ' (${s.lateToleranceMinutes} dk tolerans)' : ''}',
                        color: s.isDayOff ? t.muted : t.info,
                      ))
                  .toList(),
            ),
          const SizedBox(height: 12),
          if (status.logs.isEmpty)
            Text('Bugün kayıt yok.', style: TextStyle(fontSize: 13, color: t.muted))
          else
            ...status.logs.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Pill(text: l.typeLabel, color: l.isEntry ? t.success : t.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(fmtDateTime(l.occurredAt),
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: t.ink)),
                      ),
                      Text(
                        l.method
                            + (l.distanceM != null ? ' · ${l.distanceM!.round()} m' : ''),
                        style: TextStyle(fontSize: 12, color: t.muted),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final PdksBalance balance;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget cell(String label, String value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: t.muted)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('İzin ve Avans Durumu',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 3),
          Text('İzin yılı: ${fmtDate(balance.leaveYearFrom)} – ${fmtDate(balance.leaveYearTo)}',
              style: TextStyle(fontSize: 12, color: t.muted)),
          const SizedBox(height: 12),
          Row(
            children: [
              cell('Kalan izin', '${balance.remainingDays} gün', t.success),
              cell('Kullanılan', '${balance.usedDays} gün', t.ink),
              cell('Bekleyen', '${balance.pendingDays} gün', t.warning),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              cell('Kalan avans', fmtMoney(balance.advanceRemaining), t.success),
              cell('Aylık limit', fmtMoney(balance.advanceLimit), t.muted),
            ],
          ),
          if (balance.hourlyUsedHours > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Bu ay ${balance.hourlyUsedHours} saat saatlik izin kullanıldı '
              '(yıllık izin gününden düşülmez).',
              style: TextStyle(fontSize: 11, color: t.muted),
            ),
          ],
          ...balance.notes.map((n) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(n, style: TextStyle(fontSize: 11, color: t.muted)),
              )),
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
    final detail = r.type == 'AVANS'
        ? fmtMoney(r.amount)
        : r.type == 'IZIN'
            ? '${fmtDate(r.startAt)} – ${fmtDate(r.endAt)} (${r.days} gün)'
            : '${fmtDateTime(r.startAt)} · ${r.hours} saat';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.typeLabel,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink)),
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
          const SizedBox(height: 2),
          Text(detail, style: TextStyle(fontSize: 13, color: t.ink)),
          Text(r.reason, style: TextStyle(fontSize: 12, color: t.muted)),
          if (r.decisionNote != null)
            Text('Karar notu: ${r.decisionNote}',
                style: TextStyle(fontSize: 12, color: t.danger)),
          if (r.isPending)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onCancel, child: const Text('Geri Al')),
            ),
        ],
      ),
    );
  }
}

/// Aylik vardiya takvimi. Pazartesi ile baslar (TR takvim alisligi).
class ShiftCalendar extends StatelessWidget {
  const ShiftCalendar({super.key, required this.monthKey, required this.assignments});

  final String monthKey;
  final List<ShiftAssignment> assignments;

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

    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= dayCount; d++) {
      final date = '$monthKey-${d.toString().padLeft(2, '0')}';
      final list = byDate[date] ?? const <ShiftAssignment>[];
      final dayOff = list.any((a) => a.isDayOff);
      cells.add(Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: dayOff ? t.bg : (list.isEmpty ? t.card : t.primarySoft),
          border: Border.all(color: list.isEmpty && !dayOff ? t.border : t.primary),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$d',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.ink)),
            if (dayOff)
              Text('Tatil', style: TextStyle(fontSize: 9, color: t.muted))
            else
              ...list.take(2).map((a) => Text(
                    a.startTime ?? '',
                    style: TextStyle(fontSize: 9, color: t.muted),
                    overflow: TextOverflow.ellipsis,
                  )),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
              .map((g) => Expanded(
                    child: Text(g,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: t.muted)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.85,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
        if (assignments.isEmpty) ...[
          const SizedBox(height: 10),
          Text('Bu ay için vardiya atanmamış.',
              style: TextStyle(fontSize: 13, color: t.muted)),
        ],
      ],
    );
  }
}
