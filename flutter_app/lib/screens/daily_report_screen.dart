import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/report_export.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/daily_report.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';
import 'daily_report_dialogs.dart';

/// Gunluk operasyon raporu paneli.
///
/// Ham verileri Store Manager ve Shift Supervisor girer; oranlar sunucuda
/// hesaplanir. Ust kademeler sorumlu olduklari magazalarin raporlarini gorur.
class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  DailyReportPage _page = DailyReportPage.empty;
  ReportFields _fields = ReportFields.empty;
  String _period = 'week';
  String? _error;
  bool _loaded = false;

  static const _entryRoles = ['store_manager', 'shift_supervisor'];

  bool get _canEnter => _entryRoles.contains(session.user?.role);
  bool get _showStore => !(session.user?.storeId != null && !(session.user?.isMultiStore ?? false));

  @override
  void initState() {
    super.initState();
    _load();
    repo.reportFields().then((f) {
      if (mounted) setState(() => _fields = f);
    }).onError((Object _, StackTrace _) {});
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final page = await repo.dailyReports(period: _period, silent: silent);
      if (!mounted) return;
      setState(() {
        _page = page;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loaded = true;
      });
    }
  }

  Future<void> _enter() async {
    final ok = await showDailyReportDialog(context, fields: _fields);
    if (ok == true) {
      toastSaved('Rapor kaydedildi');
      await _load(silent: true);
    }
  }

  Future<void> _edit(DailyReport item) async {
    final ok = await showDailyReportDialog(context, fields: _fields, existing: item);
    if (ok == true) {
      toastSaved('Rapor güncellendi');
      await _load(silent: true);
    }
  }

  Future<void> _delete(DailyReport item) async {
    final ok = await confirmDialog(
      context,
      title: 'Raporu Sil',
      confirmLabel: 'Sil',
      body: Text('${fmtDate(item.date)} — ${fmtMoney(item.values['net_sales'])}'
          '\n\nBu günün raporu silinecek.'),
    );
    if (ok != true) return;
    try {
      await repo.deleteDailyReport(item);
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    await _load(silent: true);
  }

  Future<void> _export(bool pdf) async {
    if (_page.items.isEmpty) {
      toast('Dışa aktarılacak kayıt yok', kind: ToastKind.error);
      return;
    }
    try {
      if (pdf) {
        await exportReportPdf(_page, _fields, showStore: _showStore);
      } else {
        await exportReportExcel(_page, _fields, showStore: _showStore);
      }
    } catch (e) {
      toast('Dışa aktarılamadı: $e', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final summary = _page.summary;

    return CrudScaffold(
      title: 'Rapor Paneli',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      addLabel: 'Gün Ekle',
      onAdd: _canEnter ? _enter : null,
      emptyText: 'Bu dönemde rapor kaydı yok.',
      banner: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'week', label: Text('Haftalık')),
                          ButtonSegment(value: 'month', label: Text('Aylık')),
                        ],
                        selected: {_period},
                        onSelectionChanged: (v) {
                          setState(() => _period = v.first);
                          _load(silent: true);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('${fmtDate(_page.from)} – ${fmtDate(_page.to)} · ${summary.days} gün',
                    style: TextStyle(fontSize: 13, color: t.muted)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _export(false),
                        icon: const Icon(Icons.table_view_outlined, size: 18),
                        label: const Text('Excel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _export(true),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('PDF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (summary.days > 0) ...[
            const SizedBox(height: AppTokens.gap),
            _SummaryCard(summary: summary, fields: _fields),
          ],
        ],
      ),
      children: _page.items
          .map((item) => AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(fmtDate(item.date),
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
                        ),
                        Text(fmtMoney(item.values['net_sales']),
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700, color: t.success)),
                      ],
                    ),
                    if (_showStore && item.storeName != null) ...[
                      const SizedBox(height: 4),
                      Text(item.storeName!, style: TextStyle(fontSize: 12, color: t.muted)),
                    ],
                    const SizedBox(height: 8),
                    _MetricWrap(fields: _fields, report: item),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${fmtInt(item.values['adt'])} fiş · '
                            '${fmtInt(item.values['product_qty'])} ürün · '
                            '${item.createdByName ?? 'bilinmiyor'}',
                            style: TextStyle(fontSize: 12, color: t.muted),
                          ),
                        ),
                        TextButton(
                          onPressed: () => showDailyReportDetail(context, item, _fields),
                          child: const Text('Detay'),
                        ),
                        // Girisi yapan roller kendi kayitlarini duzeltebilir.
                        if (_canEnter) ...[
                          IconButton(
                            tooltip: 'Düzenle',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _edit(item),
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                          IconButton(
                            tooltip: 'Sil',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _delete(item),
                            icon: Icon(Icons.delete_outline, size: 19, color: t.danger),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

/// Karttaki turetilen olculer.
class _MetricWrap extends StatelessWidget {
  const _MetricWrap({required this.fields, required this.report});

  final ReportFields fields;
  final DailyReport report;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: fields.derived
          .map((f) => Pill(
                text: '${f.label}: ${formatReportValue(report.metrics[f.key], f.type)}',
                color: f.key == 'food_markout_pct' ? t.danger : t.info,
              ))
          .toList(),
    );
  }
}

/// Donem ozeti: ham toplamlar + toplamlardan hesaplanan oranlar.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.fields});

  final ReportSummaryTotals summary;
  final ReportFields fields;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dönem Özeti',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 4),
          Text('Oranlar günlerin ortalaması değil, toplam veriden hesaplanır.',
              style: TextStyle(fontSize: 12, color: t.muted)),
          const SizedBox(height: 12),
          ...fields.entry.map((f) => _Row(
                label: f.label,
                value: formatReportValue(summary.totals[f.key], f.type),
              )),
          ...fields.system.map((f) => _Row(
                label: f.label,
                value: formatReportValue(summary.totals[f.key], f.type),
              )),
          const Divider(height: 20),
          ...fields.derived.map((f) => _Row(
                label: f.label,
                value: formatReportValue(summary.metrics[f.key], f.type),
                bold: true,
              )),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: bold ? t.ink : t.muted,
                    fontWeight: bold ? FontWeight.w600 : FontWeight.w500)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: bold ? t.primary : t.ink)),
        ],
      ),
    );
  }
}
