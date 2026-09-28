import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/report_export.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../core/new_theme.dart';
import '../models/daily_report.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';
import 'daily_report_dialogs.dart';

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
  bool get _showStore =>
      !(session.user?.storeId != null &&
          !(session.user?.isMultiStore ?? false));

  @override
  void initState() {
    super.initState();
    _load();
    repo
        .reportFields()
        .then((f) {
          if (mounted) setState(() => _fields = f);
        })
        .onError((Object _, StackTrace _) {});
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
    final ok = await showDailyReportDialog(
      context,
      fields: _fields,
      existing: item,
    );
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
      body: Text(
        '${fmtDate(item.date)} — ${fmtMoney(item.values['net_sales'])}'
        '\n\nBu günün raporu silinecek.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteDailyReport(item);
    } catch (_) {
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
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: NewTokens.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final itemsCount = _page.items.length;
    final totalSales = _page.summary.totals['net_sales'] ?? 0.0;
    
    return Scaffold(
      backgroundColor: NewTokens.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildTopTitleBar(),
                      const SizedBox(height: 12),
                      _buildPageSwitcher(),
                      const SizedBox(height: 12),
                      _buildToolbar(),
                      const SizedBox(height: 12),
                      _buildDocumentCard(itemsCount, totalSales),
                      const SizedBox(height: 12),
                      _buildExportCard(),
                      const SizedBox(height: 12),
                      _buildBottomActions(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: NewTokens.surface.withOpacity(0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 1),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: NewTokens.onSurfaceVariant),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pdf Rapor Önizleme Modalı', style: NewTokens.headlineSm.copyWith(fontSize: 16, color: NewTokens.onSurface)),
                  Text('Colombia Coffee · Resmi Döküman', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.share, color: NewTokens.onSurfaceVariant),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.download, color: NewTokens.primary),
                onPressed: () => _export(true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopTitleBar() {
    return Column(
      children: [
        Container(
          width: 48,
          height: 6,
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: NewTokens.primaryContainer.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.picture_as_pdf, color: NewTokens.primaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('PDF Rapor Önizleme', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: NewTokens.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('Sayfa 2 / 2', style: NewTokens.labelSm.copyWith(color: NewTokens.onSecondaryContainer)),
                              ),
                            ],
                          ),
                          Text('Düzce Merkez Şube · Hareket & Denetim Günlüğü Dökümü', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: NewTokens.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.first_page, size: 18, color: NewTokens.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.description, size: 16, color: NewTokens.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('1: Yönetici Özeti & Onay', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bar_chart, size: 16, color: NewTokens.primaryContainer),
                  const SizedBox(width: 6),
                  Text('2: Ek Döküm & Analiz', style: NewTokens.labelMd.copyWith(color: NewTokens.primaryContainer)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: NewTokens.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text('Ek Döküm & Analiz Aktif', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.remove, size: 16, color: NewTokens.onSurfaceVariant),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('100%', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurface)),
                    ),
                    const Icon(Icons.add, size: 16, color: NewTokens.onSurfaceVariant),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chevron_left, size: 16, color: NewTokens.onSurfaceVariant),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('2/2', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurface)),
                    ),
                    const Icon(Icons.chevron_right, size: 16, color: NewTokens.outlineVariant),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.fullscreen, size: 16, color: NewTokens.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(int itemsCount, double totalSales) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: NewTokens.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text('☕', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('COLOMBIA COFFEE', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface, letterSpacing: 1.2)),
                      Text('İç Denetim ve Operasyon Direktörlüğü', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: NewTokens.primaryContainer.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('EK-1 ANALİZ', style: NewTokens.labelSm.copyWith(color: NewTokens.primaryContainer, fontSize: 10)),
                  ),
                  const SizedBox(height: 2),
                  Text('Doküman No: CC-2026/09-DZ-EK', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 9)),
                  Text('A4 / DİKEY FORMAT', style: NewTokens.labelSm.copyWith(color: NewTokens.outline, fontSize: 9)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: NewTokens.surfaceContainer),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EK DÖKÜM, KATEGORİ DAĞILIMI & SAATLİK YOĞUNLUK ANALİZİ', style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface, fontSize: 14)),
                Text('Düzce Merkez Şube Günlük İşlem Hacmi ve Güvenlik Denetim Özeti', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.show_chart, size: 16, color: NewTokens.primaryContainer),
                  const SizedBox(width: 6),
                  Text('Saatlik Operasyonel Yoğunluk Grafiği', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface)),
                ],
              ),
              Text('08:00 - 02:00 Vardiyaları', style: NewTokens.labelSm.copyWith(color: NewTokens.outlineVariant, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: NewTokens.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: NewTokens.primaryContainer, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Öğle Piki', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 10)),
                          Text('12:00-14:00 (42 İşlem)', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: NewTokens.secondaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: NewTokens.secondary, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Akşam Piki', style: NewTokens.labelSm.copyWith(color: NewTokens.onSecondaryContainer, fontSize: 10)),
                          Text('19:00-21:00 (58 İşlem)', style: NewTokens.labelMd.copyWith(color: NewTokens.onSecondaryContainer)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 96,
            width: double.infinity,
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainerLow.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildBar('08', 18, NewTokens.secondaryFixedDim),
                _buildBar('10', 36, NewTokens.primaryContainer),
                _buildBar('12', 56, NewTokens.primary, dot: true),
                _buildBar('14', 42, NewTokens.primaryContainer),
                _buildBar('16', 31, NewTokens.secondaryFixedDim),
                _buildBar('18', 48, NewTokens.primaryContainer),
                _buildBar('20', 70, NewTokens.primary, dot: true),
                _buildBar('22', 44, NewTokens.primaryContainer),
                _buildBar('00', 28, NewTokens.secondaryFixedDim),
                _buildBar('02', 13, NewTokens.outlineVariant),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('İşlem Türü Dağılımı ve Güvenlik Sınıflandırması', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface)),
              Text('Toplam ${itemsCount > 0 ? itemsCount : 268} Olay', style: NewTokens.labelSm.copyWith(color: NewTokens.outlineVariant, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildCatCard('Vardiya & PDKS', '%81,4', 81.4, NewTokens.primaryContainer, '184 İşlem Onaylandı', NewTokens.surfaceContainerLow),
              _buildCatCard('Finans & Kasa', '%18,6', 18.6, NewTokens.secondary, '42 Mali Döküm İşlemi', NewTokens.surfaceContainerLow),
              _buildCatCard('Güvenlik & IP', '38 Log', 48.0, NewTokens.outlineVariant, 'Mobil & POS Doğrulaması', NewTokens.surfaceContainerLow),
              _buildCatCard('Kritik Olaylar', '4 Olay', 15.0, NewTokens.error, '2 Zayi, 2 Yetki Onayı', NewTokens.errorContainer.withOpacity(0.4), titleColor: NewTokens.onErrorContainer, valueColor: NewTokens.error, subtitleColor: NewTokens.onErrorContainer),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Örnek Güvenlik Denetim Günlüğü Dökümü', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface)),
              Text('EK ÇİZELGE A-4', style: NewTokens.labelSm.copyWith(color: NewTokens.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: NewTokens.surfaceContainer,
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('Saat', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 10))),
                      Expanded(flex: 4, child: Text('Kategori', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 10))),
                      Expanded(flex: 3, child: Text('Kullanıcı', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 10))),
                      Expanded(flex: 3, child: Text('Durum', textAlign: TextAlign.right, style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 10))),
                    ],
                  ),
                ),
                _buildTableRow('02:39', 'VARDIYA_PAYLAS', 'Mobil App (iOS)', 'talat', 'Onaylandı', NewTokens.secondaryContainer, NewTokens.onSecondaryContainer, false),
                _buildTableRow('02:33', 'GIRIS', 'Mobil (Android)', 'm.sukrusezer', 'Başarılı', NewTokens.secondaryContainer, NewTokens.onSecondaryContainer, true),
                _buildTableRow('01:15', 'ZAYI_KAYIT', 'POS-01 (Kasa)', 'm.sukrusezer', '2 Ad. Zayi', NewTokens.errorContainer, NewTokens.onErrorContainer, false),
                _buildTableRow('00:45', 'KASA_DENKLIK', 'POS-01 (Kasa)', 'talat', '+0,00 ₺', NewTokens.surfaceContainer, NewTokens.onSurface, true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: NewTokens.surfaceContainer),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.qr_code_2, size: 20, color: NewTokens.primary),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SHA-256 E-İmza Özeti', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurface, fontSize: 10)),
                      const Text('8f4be1c7849d...39e102bc91', style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: NewTokens.outline)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NewTokens.primaryContainer.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, size: 14, color: NewTokens.primaryContainer),
                    const SizedBox(width: 4),
                    Text('E-MÜHÜR ONAYLI', style: NewTokens.labelSm.copyWith(color: NewTokens.primaryContainer, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bu ek döküm 6698 sayılı KVKK ve Vergi Usul Kanunu standartlarındadır.', style: NewTokens.labelSm.copyWith(color: NewTokens.outline, fontSize: 9)),
              Text('Sayfa 2 / 2', style: NewTokens.labelSm.copyWith(color: NewTokens.outline, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBar(String label, double height, Color color, {bool dot = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (dot) Container(width: 6, height: 6, margin: const EdgeInsets.only(bottom: 4), decoration: const BoxDecoration(color: NewTokens.error, shape: BoxShape.circle)),
        Container(
          width: 16,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 8, color: NewTokens.onSurfaceVariant, fontWeight: dot ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }

  Widget _buildCatCard(String title, String value, double percent, Color fill, String subtitle, Color bg, {Color? titleColor, Color? valueColor, Color? subtitleColor}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: NewTokens.labelSm.copyWith(color: titleColor ?? NewTokens.onSurfaceVariant, fontSize: 11)),
              Text(value, style: NewTokens.labelMd.copyWith(color: valueColor ?? fill)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: percent / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: NewTokens.bodySm.copyWith(color: subtitleColor ?? NewTokens.outline, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildTableRow(String time, String cat, String subcat, String user, String status, Color statusBg, Color statusText, bool alternate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: alternate ? NewTokens.surfaceContainerLowest.withOpacity(0.5) : Colors.transparent,
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(time, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: NewTokens.outline))),
          Expanded(flex: 4, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat, style: NewTokens.labelSm.copyWith(color: NewTokens.onSurface), overflow: TextOverflow.ellipsis),
              Text(subcat, style: const TextStyle(fontSize: 9, color: NewTokens.outline)),
            ],
          )),
          Expanded(flex: 3, child: Text(user, style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(status, style: NewTokens.labelSm.copyWith(color: statusText, fontSize: 9)),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildExportCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_2, color: NewTokens.primary, size: 20),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('denetim_gunlugu_duzce_20260927_tam.pdf', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface)),
                      Text('2 Sayfa · 2.1 MB · 300 DPI Vektörel Baskı Hazır', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: NewTokens.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Resmi', style: NewTokens.labelSm.copyWith(color: NewTokens.onSecondaryContainer, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: NewTokens.surfaceContainer),
          const SizedBox(height: 12),
          _buildToggleRow(Icons.vpn_key, NewTokens.primaryContainer, 'Dijital İmza & E-Mühür Ekle', true),
          const SizedBox(height: 8),
          _buildToggleRow(Icons.query_stats, NewTokens.primaryContainer, 'Grafik & Analiz Katmanlarını Dahil Et', true),
          const SizedBox(height: 8),
          _buildToggleRow(Icons.lock, NewTokens.outline, 'Detaylı IP / Cihaz Bilgisini Maskele', false, textColor: NewTokens.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildToggleRow(IconData icon, Color iconColor, String text, bool checked, {Color? textColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Text(text, style: NewTokens.labelMd.copyWith(color: textColor ?? NewTokens.onSurface)),
          ],
        ),
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: checked,
            onChanged: (v) {},
            activeColor: NewTokens.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () => _export(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: NewTokens.primaryContainer,
            foregroundColor: NewTokens.onPrimary,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.download, size: 20),
              const SizedBox(width: 8),
              Text('Tam Raporu İndir (2 Sayfa PDF)', style: NewTokens.labelLg),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: NewTokens.surfaceContainer,
                  foregroundColor: NewTokens.onSurface,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.print, size: 18, color: NewTokens.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text('Yazdır (AirPrint)', style: NewTokens.labelMd),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: NewTokens.surfaceContainer,
                  foregroundColor: NewTokens.onSurface,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.send, size: 18, color: NewTokens.secondary),
                    const SizedBox(width: 6),
                    Text('WhatsApp / Mail', style: NewTokens.labelMd),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
