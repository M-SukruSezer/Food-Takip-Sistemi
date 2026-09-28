import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/new_theme.dart';
import '../models/pdks.dart';
import '../models/store.dart';

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
      return Scaffold(
        backgroundColor: NewTokens.surface,
        appBar: AppBar(
          backgroundColor: NewTokens.surface,
          title: const Text('Mağaza Seçin', style: NewTokens.headlineSm),
        ),
        body: _loaded
            ? ListView.builder(
                itemCount: _stores.length,
                itemBuilder: (context, index) {
                  final s = _stores[index];
                  return ListTile(
                    title: Text(s.name, style: NewTokens.bodyLg),
                    onTap: () {
                      setState(() {
                        _selected = s;
                        _report = null;
                      });
                      _loadReport();
                    },
                  );
                },
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    
    final summary = _report?.total;
    
    return Scaffold(
      backgroundColor: NewTokens.surface,
      appBar: AppBar(
        backgroundColor: NewTokens.surface.withOpacity(0.85),
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.03),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ColorFilter.mode(Colors.transparent, BlendMode.srcOver),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: NewTokens.tertiaryContainer, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  _selected!.name,
                  style: NewTokens.labelSm.copyWith(color: NewTokens.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Text(
              'İzin & Vardiya Talepleri',
              style: NewTokens.headlineSm,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: NewTokens.onSurfaceVariant),
            onPressed: () {},
          ),
          Container(
            width: 32, height: 32,
            margin: const EdgeInsets.only(right: 16),
            decoration: const BoxDecoration(color: NewTokens.primary, shape: BoxShape.circle),
            child: const Icon(Icons.person, color: NewTokens.onPrimary, size: 18),
          ),
        ],
      ),
      body: _loadingReport && _report == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadReport(silent: true),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  // Context Strip
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'İzin & Vardiya Talepleri',
                                style: NewTokens.headlineSm.copyWith(fontWeight: FontWeight.bold, color: NewTokens.onSurface),
                              ),
                              Text(
                                '${_selected!.name} · Personel Puantajı',
                                style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: NewTokens.primary,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.add, color: NewTokens.onPrimary, size: 18),
                              const SizedBox(width: 6),
                              Text('Yeni Talep', style: NewTokens.labelMd.copyWith(color: NewTokens.onPrimary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Segmented
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: NewTokens.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Bekleyenler', style: NewTokens.labelMd.copyWith(color: NewTokens.primary)),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 20, height: 20,
                                    decoration: const BoxDecoration(color: NewTokens.primaryContainer, shape: BoxShape.circle),
                                    alignment: Alignment.center,
                                    child: Text('3', style: NewTokens.labelSm.copyWith(color: NewTokens.onPrimaryContainer, fontSize: 11)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Onaylananlar', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurfaceVariant)),
                                  const SizedBox(width: 4),
                                  Text('(14)', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text('Geçmiş', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurfaceVariant)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Manager Operational KPI Trio
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: NewTokens.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Icon(Icons.pending_actions, color: NewTokens.primary, size: 20),
                                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: NewTokens.error, shape: BoxShape.circle)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(summary?.leaveDays.toString() ?? '3', style: NewTokens.numericMetric.copyWith(fontSize: 22, color: NewTokens.onSurface)),
                                Text('Bekleyen Talep', style: NewTokens.labelSm.copyWith(fontSize: 11, color: NewTokens.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text('2 Takas · 1 Mazeret', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.secondary, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: NewTokens.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Icon(Icons.beach_access, color: NewTokens.tertiary, size: 20),
                                    Text('Bu Hafta', style: NewTokens.labelSm.copyWith(fontSize: 11, color: NewTokens.tertiary)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(summary?.absentDays.toString() ?? '2', style: NewTokens.numericMetric.copyWith(fontSize: 22, color: NewTokens.onSurface)),
                                Text('İzinli Personel', style: NewTokens.labelSm.copyWith(fontSize: 11, color: NewTokens.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text('Talat H. · Sena Ü.', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: NewTokens.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Icon(Icons.check_circle, color: NewTokens.tertiaryContainer, size: 20),
                                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: NewTokens.tertiary, shape: BoxShape.circle)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('0', style: NewTokens.numericMetric.copyWith(fontSize: 22, color: NewTokens.tertiary)),
                                Text('Vardiya Açığı', style: NewTokens.labelSm.copyWith(fontSize: 11, color: NewTokens.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text('Kadro Tam', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.tertiary)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: NewTokens.primary,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
                          ),
                          child: Row(
                            children: [
                              Text('Tümü', style: NewTokens.labelMd.copyWith(color: NewTokens.onPrimary)),
                              const SizedBox(width: 6),
                              Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(color: NewTokens.onPrimary.withOpacity(0.2), shape: BoxShape.circle),
                                alignment: Alignment.center,
                                child: Text('3', style: NewTokens.labelSm.copyWith(color: NewTokens.onPrimary, fontSize: 10)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: NewTokens.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.swap_horiz, color: NewTokens.onSurfaceVariant, size: 16),
                              const SizedBox(width: 6),
                              Text('Vardiya Takas', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurfaceVariant)),
                              const SizedBox(width: 4),
                              Text('(2)', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant.withOpacity(0.8), fontSize: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: NewTokens.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_busy, color: NewTokens.onSurfaceVariant, size: 16),
                              const SizedBox(width: 6),
                              Text('Yıllık & Mazeret İzin', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurfaceVariant)),
                              const SizedBox(width: 4),
                              Text('(1)', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant.withOpacity(0.8), fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Feed
                  if (_report != null) ..._report!.items.map((person) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: NewTokens.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: const BoxDecoration(
                                    color: NewTokens.secondaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    person.fullName.substring(0, 2).toUpperCase(),
                                    style: NewTokens.headlineSm.copyWith(color: NewTokens.onSecondaryContainer, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        person.fullName,
                                        style: NewTokens.headlineSm.copyWith(fontSize: 15, color: NewTokens.onSurface),
                                      ),
                                      Text(
                                        'Çalışılan: ${fmtDuration(person.summary.workedMinutes)}',
                                        style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: NewTokens.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: NewTokens.primary, shape: BoxShape.circle)),
                                      const SizedBox(width: 4),
                                      Text('İncelemede', style: NewTokens.labelSm.copyWith(color: NewTokens.onSecondaryContainer, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  
                  // Info Box
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info, color: NewTokens.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant, height: 1.5),
                                children: [
                                  TextSpan(text: 'Operasyon Kuralı: ', style: NewTokens.bodySm.copyWith(fontWeight: FontWeight.bold, color: NewTokens.onSurface)),
                                  const TextSpan(text: 'Vardiya takasları başlangıç saatinden en geç 12 saat önce, resmi izin talepleri ise en az 3 iş günü önce şube müdürü tarafından onaylanmalıdır. Onaylanan değişiklikler Düzce Merkez PDKS terminaline ve haftalık çizelgeye otomatik yansıtılır.'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
