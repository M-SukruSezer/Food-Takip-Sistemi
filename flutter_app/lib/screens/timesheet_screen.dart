import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/pdks.dart';
import '../models/store.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/panels.dart';

/// IK ekrani: magaza listesi -> secilen magazanin personel puantaji.
///
/// Neden Devam Yonetimi'nden ayri bir ekran: IK rolu yalnizca /stores ve
/// /pdks/timesheet uclarina erisiyor. Devam Yonetimi acilisinda anlik durum,
/// vardiya ve talep uclarini da cagiriyor; IK'da hepsi 403 doner ve ekran
/// hatayla acilirdi. Bu ekran yalnizca izin verilen iki ucu kullaniyor.
class TimesheetScreen extends StatefulWidget {
  const TimesheetScreen({super.key});

  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  List<Store> _stores = const [];
  Store? _selected;

  TimesheetReport? _report;
  DateTime _month = DateTime.now();
  bool _loaded = false;
  bool _loadingReport = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  String get _from => ymd(DateTime(_month.year, _month.month, 1));
  String get _to => ymd(DateTime(_month.year, _month.month + 1, 0));

  Future<void> _loadStores({bool silent = false}) async {
    try {
      final list = await repo.storeList(silent: silent);
      if (!mounted) return;
      setState(() {
        _stores = list.where((s) => s.active).toList();
        _loaded = true;
        _error = null;
        // Tek magazaya atanmis IK kullanicisinda araya liste koymak gereksiz
        // bir dokunus; dogrudan puantaja gidiliyor.
        if (_selected == null && _stores.length == 1) _selected = _stores.first;
      });
      if (_selected != null) await _loadReport();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _error = errorMessage(e);
      });
    }
  }

  Future<void> _loadReport({bool silent = false}) async {
    final store = _selected;
    if (store == null) return;
    setState(() => _loadingReport = true);
    try {
      final r = await repo.pdksTimesheet(
        from: _from,
        to: _to,
        storeId: store.id,
        silent: silent,
      );
      if (!mounted) return;
      setState(() {
        _report = r;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _error = errorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loadingReport = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _loadReport();
  }

  @override
  Widget build(BuildContext context) {
    if (_selected == null) {
      return CrudScaffold(
        title: 'Puantaj — Mağaza Seçin',
        loaded: _loaded,
        error: _error,
        onRetry: _loadStores,
        onRefresh: () => _loadStores(silent: true),
        emptyText: 'Size mağaza atanmamış. Yöneticinizle görüşün.',
        grid: true,
        children: _stores
            .map(
              (s) => _StoreCard(
                store: s,
                onTap: () {
                  setState(() {
                    _selected = s;
                    _report = null;
                  });
                  _loadReport();
                },
              ),
            )
            .toList(),
      );
    }
    return _StoreTimesheet(
      store: _selected!,
      report: _report,
      month: _month,
      loading: _loadingReport,
      error: _error,
      // Tek magazaya atanmis kullanicida geri donecek liste yok.
      onBack: _stores.length > 1
          ? () => setState(() {
              _selected = null;
              _report = null;
              _error = null;
            })
          : null,
      onMonth: _shiftMonth,
      onRefresh: () => _loadReport(silent: true),
      onRetry: _loadReport,
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.onTap});

  final Store store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radius),
      onTap: onTap,
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: t.primarySoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Icon(Icons.store_outlined, color: t.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${store.userCount} personel',
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.muted),
          ],
        ),
      ),
    );
  }
}

class _StoreTimesheet extends StatelessWidget {
  const _StoreTimesheet({
    required this.store,
    required this.report,
    required this.month,
    required this.loading,
    required this.error,
    required this.onBack,
    required this.onMonth,
    required this.onRefresh,
    required this.onRetry,
  });

  final Store store;
  final TimesheetReport? report;
  final DateTime month;
  final bool loading;
  final String? error;
  final VoidCallback? onBack;
  final ValueChanged<int> onMonth;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final people = report?.items ?? const <TimesheetPerson>[];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    tooltip: 'Mağaza listesi',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    constraints: const BoxConstraints(
                      minWidth: AppTokens.tap,
                      minHeight: AppTokens.tap,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        monthLabel(month),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Önceki ay',
                  onPressed: loading ? null : () => onMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Sonraki ay',
                  onPressed: loading ? null : () => onMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppTokens.gap),
            AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppAlert(message: error!),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            ),
          ] else if (loading && report == null) ...[
            const SizedBox(height: AppTokens.gap),
            const AppCard(child: Text('Puantaj hesaplanıyor...')),
          ] else if (people.isEmpty) ...[
            const SizedBox(height: AppTokens.gap),
            const AppCard(child: Text('Bu mağazada aktif personel yok.')),
          ] else ...[
            const SizedBox(height: AppTokens.gap),
            _Totals(summary: report!.total),
            const SizedBox(height: AppTokens.gap),
            ...people.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.gap),
                child: _PersonRow(person: p),
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: report!.notes
                    .map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $n',
                          style: TextStyle(color: t.muted, fontSize: 11.5),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.summary});

  final TimesheetSummary summary;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String)>[
      ('Çalışılan', fmtDuration(summary.workedMinutes)),
      ('Planlı', fmtDuration(summary.scheduledMinutes)),
      ('Fazla mesai', fmtDuration(summary.overtimeMinutes)),
      ('Eksik', fmtDuration(summary.missingMinutes)),
      ('Devamsız gün', '${summary.absentDays}'),
      ('İzinli gün', '${summary.leaveDays}'),
    ];
    return AppCard(
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        children: cells.map((c) => _Figure(label: c.$1, value: c.$2)).toList(),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: t.ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final TimesheetPerson person;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = person.summary;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  person.fullName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Text(
                roleLabels[person.role] ?? '',
                style: TextStyle(
                  color: t.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _Figure(label: 'Çalışılan', value: fmtDuration(s.workedMinutes)),
              _Figure(label: 'Planlı', value: fmtDuration(s.scheduledMinutes)),
              _Figure(label: 'Fazla', value: fmtDuration(s.overtimeMinutes)),
              _Figure(label: 'Eksik', value: fmtDuration(s.missingMinutes)),
              _Figure(label: 'Devamsız', value: '${s.absentDays} gün'),
              _Figure(label: 'İzinli', value: '${s.leaveDays} gün'),
            ],
          ),
          // Cihaz uyarilari: puantaji okuyan kisi supheli bir girisi gormeden
          // imzalamasin. Bu kayitlar KABUL EDILDI; engellenenler hic yazilmaz.
          if (s.flaggedDays > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: t.warningSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: t.warningText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${s.flaggedDays} günde cihaz uyarısı var',
                      style: TextStyle(
                        color: t.warningText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
