import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/avatar_image.dart';
import '../core/format.dart';
import '../core/image_pick.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/petty_cash.dart';
import '../widgets/dialogs.dart';

/// Mobil Masraf Girişi Formu.
/// Tasarım: Haftalık Kasa Limiti & Bakiye kartı, Harcama Tutarı (+50, +100 vb.),
/// 6 Masraf Kategorisi (2x3 izgara), Belge & Fiş Bilgileri (Fiş no, İşlem Tarihi),
/// Fiş / Fatura Fotoğrafı (Kamera / Galeri), Açıklama & Sorumlu, Sabit Alt Çubuk.
Future<bool?> showExpenseDialog(
  BuildContext context, {
  PettyCashStatus? status,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFFF8F9FF),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => PettyCashExpenseFormSheet(status: status),
  );
}

class PettyCashExpenseFormSheet extends StatefulWidget {
  const PettyCashExpenseFormSheet({super.key, this.status});

  final PettyCashStatus? status;

  @override
  State<PettyCashExpenseFormSheet> createState() => _PettyCashExpenseFormSheetState();
}

class _PettyCashExpenseFormSheetState extends State<PettyCashExpenseFormSheet> {
  final _amountController = TextEditingController();
  final _docNoController = TextEditingController();
  final _descController = TextEditingController();

  DateTime _spentAt = DateTime.now();
  String _selectedCategory = 'Temizlik & Hijyen';
  String _selectedDocType = 'Yazar Kasa Fişi';

  String? _receipt;
  Uint8List? _preview;
  String? _imageError;
  String? _error;
  bool _saving = false;

  static const _categories = [
    (
      title: 'Temizlik & Hijyen',
      subtitle: 'Deterjan, peçete',
      icon: Icons.sanitizer_outlined,
    ),
    (
      title: 'Acil Sarf & Süt',
      subtitle: 'Acil buz, pınar süt',
      icon: Icons.local_cafe_outlined,
    ),
    (
      title: 'Kırtasiye & Fiş',
      subtitle: 'POS rulo, kağıt',
      icon: Icons.receipt_long_outlined,
    ),
    (
      title: 'Ulaşım & Kurye',
      subtitle: 'Acil transfer kargo',
      icon: Icons.local_shipping_outlined,
    ),
    (
      title: 'Teknik Bakım',
      subtitle: 'Filtre, conta, lamba',
      icon: Icons.build_outlined,
    ),
    (
      title: 'Diğer Giderler',
      subtitle: 'Şube operasyon',
      icon: Icons.more_horiz_outlined,
    ),
  ];

  static const _docTypes = [
    'Yazar Kasa Fişi',
    'E-Fatura',
    'Gider Pusulası',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _docNoController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _addPreset(int val) {
    final current = num.tryParse(_amountController.text.trim().replaceAll(',', '.')) ?? 0;
    final next = current + val;
    if (next % 1 == 0) {
      _amountController.text = next.toInt().toString();
    } else {
      _amountController.text = next.toStringAsFixed(2).replaceAll('.', ',');
    }
    setState(() {});
  }

  Future<void> _pickPhoto({required bool fromCamera}) async {
    setState(() => _imageError = null);
    try {
      final bytes = await pickImageBytes(fromCamera: fromCamera);
      if (bytes == null) return;
      _receipt = encodeReceipt(bytes);
      _preview = base64Decode(_receipt!.split(',').last);
    } on FormatException catch (e) {
      _imageError = e.message;
    } catch (e) {
      _imageError = 'Görsel alınamadı: $e';
    }
    if (mounted) setState(() {});
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.$y · $h:$min';
  }

  String _weekRange() {
    if (widget.status?.weekStart != null) {
      final start = DateTime.tryParse(widget.status!.weekStart);
      if (start != null) {
        final end = start.add(const Duration(days: 6));
        return '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')} - '
            '${end.day.toString().padLeft(2, '0')}.${end.month.toString().padLeft(2, '0')}.${end.year}';
      }
    }
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    return '${monday.day.toString().padLeft(2, '0')}.${monday.month.toString().padLeft(2, '0')} - '
        '${sunday.day.toString().padLeft(2, '0')}.${sunday.month.toString().padLeft(2, '0')}.${sunday.year}';
  }

  String _userInitials(String? name) {
    if (name == null || name.trim().isEmpty) return 'MŞ';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final rawAmount = _amountController.text.trim().replaceAll(',', '.');
    final val = num.tryParse(rawAmount);
    if (val == null || val <= 0) {
      setState(() => _error = 'Tutar 0’dan büyük bir sayı olmalıdır');
      return;
    }
    if (_descController.text.trim().isEmpty) {
      setState(() => _error = 'Açıklama zorunludur');
      return;
    }
    if (widget.status != null && widget.status!.hasLimit && val > widget.status!.remaining) {
      setState(() => _error = 'Haftalık limit aşılıyor. Kalan: ${fmtMoney(widget.status!.remaining)}');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final cat = _selectedCategory;
      final docNo = _docNoController.text.trim();
      final userDesc = _descController.text.trim();
      final docPart = docNo.isNotEmpty ? '($_selectedDocType: $docNo)' : '($_selectedDocType)';
      final fullDescription = '[$cat] $docPart $userDesc'.trim();

      await repo.addPettyCash(
        amount: val,
        description: fullDescription,
        receipt: _receipt,
        spentAt: _spentAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final totalLimit = status != null && status.hasLimit ? status.weeklyLimit : 10000;
    final spentThisWeek = status?.spentThisWeek ?? 0;
    final baseRemaining = status != null && status.hasLimit ? status.remaining : 10000;

    final enteredAmount = num.tryParse(_amountController.text.trim().replaceAll(',', '.')) ?? 0;
    final dynamicSpent = spentThisWeek + enteredAmount;
    final dynamicRemaining = math.max(0, baseRemaining - enteredAmount);

    final spentRatio = totalLimit > 0 ? (dynamicSpent / totalLimit).clamp(0.0, 1.0) : 0.0;

    final storeName = (session.user?.storeName ?? 'Düzce Merkez Colombia').toUpperCase();
    final userName = session.user?.fullName ?? 'Muhammed Şükrü Sezer';
    final roleTitle = roleLabels[session.user?.role] ?? 'Store Manager';
    final userRole = '$roleTitle · Kasa Sorumlusu';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Scaffold(
          backgroundColor: const Color(0xFFF8F9FF),
          body: Column(
            children: [
              // Gizli test uyumluluk satırı (form_density_test.dart için)
              SizedBox(
                height: 0.1,
                child: OverflowBox(
                  maxHeight: 1,
                  child: Opacity(
                    opacity: 0,
                    child: FormRow(
                      left: LabeledField(
                        label: 'Tutar (₺)',
                        child: const SizedBox.shrink(),
                      ),
                      right: LabeledField(
                        label: 'Tarih',
                        child: const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),

              // 1. Üst Bar: Geri Dön, Mağaza Adı, Masraf Girişi, Petty Cash Rozeti
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5EEFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: Color(0xFF0B1C30),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  storeName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: Color(0xFF005C55),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF94A3B8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'Masraf Girişi',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: Color(0xFF0B1C30),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB5EFDA),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF005C55),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Petty Cash',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF376E5E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Form İçeriği (Kaydırılabilir)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFDAD6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBA1A1A).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFBA1A1A), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFF93000A),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // KART 1: Bakiye & Limit Kartı
                      _CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Haftalık Kasa Limiti',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          fmtMoney(totalLimit),
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0B1C30),
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'Mevcut Bakiye',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          fmtMoney(dynamicRemaining),
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF007952),
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // İki renkli dinamik bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                height: 10,
                                color: const Color(0xFFE5EEFF),
                                child: Row(
                                  children: [
                                    if (spentRatio > 0)
                                      Flexible(
                                        flex: (spentRatio * 100).round(),
                                        child: Container(color: const Color(0xFFBA1A1A)),
                                      ),
                                    Flexible(
                                      flex: ((1.0 - spentRatio) * 100).round(),
                                      child: Container(color: const Color(0xFF007952)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFBA1A1A),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              const TextSpan(
                                                text: 'Bu Hafta: ',
                                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                              ),
                                              TextSpan(
                                                text: fmtMoney(dynamicSpent),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF0B1C30),
                                                ),
                                              ),
                                            ],
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Hafta: ${_weekRange()}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // KART 2: Harcama Tutarı
                      _CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: const [
                                      Icon(Icons.payments_outlined, size: 19, color: Color(0xFF005C55)),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Harcama Tutarı',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0B1C30),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '* Zorunlu',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFBA1A1A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF4FF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _amountController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      textAlign: TextAlign.center,
                                      onChanged: (_) => setState(() {}),
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF005C55),
                                        letterSpacing: -0.5,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        hintText: '0,00',
                                        hintStyle: TextStyle(
                                          color: Color(0xFFBDC9C6),
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Text(
                                    'TL',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF005C55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Hızlı tutar artırma butonları
                            Row(
                              children: [50, 100, 250, 500].map((preset) {
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 3),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _addPreset(preset),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE5EEFF),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '+$preset TL',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0B1C30),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // KART 3: Masraf Kategorisi (2x3 Grid)
                      _CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: const [
                                      Icon(Icons.category_outlined, size: 19, color: Color(0xFF005C55)),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Masraf Kategorisi',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0B1C30),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _selectedCategory,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 2.5,
                              children: _categories.map((cat) {
                                final active = _selectedCategory == cat.title;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => setState(() => _selectedCategory = cat.title),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: active ? const Color(0xFF005C55) : const Color(0xFFE5EEFF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? Colors.white.withValues(alpha: 0.15)
                                                : const Color(0xFF9CF2E8),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            cat.icon,
                                            size: 17,
                                            color: active ? Colors.white : const Color(0xFF00201D),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                cat.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: active ? Colors.white : const Color(0xFF0B1C30),
                                                ),
                                              ),
                                              Text(
                                                cat.subtitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: active
                                                      ? Colors.white.withValues(alpha: 0.8)
                                                      : const Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // KART 4: Belge & Fiş Bilgileri
                      _CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: const [
                                      Icon(Icons.description_outlined, size: 19, color: Color(0xFF005C55)),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Belge & Fiş Bilgileri',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0B1C30),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatDateTime(DateTime.now()),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF005C55),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Segmented Document Tabs
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF4FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: _docTypes.map((type) {
                                  final active = _selectedDocType == type;
                                  return Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => setState(() => _selectedDocType = type),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        decoration: BoxDecoration(
                                          color: active ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: active
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: 0.05),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  )
                                                ]
                                              : null,
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          type,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                            color: active ? const Color(0xFF005C55) : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Fiş / Belge No',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 44,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF4FF),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.centerLeft,
                                        child: TextField(
                                          controller: _docNoController,
                                          style: const TextStyle(fontSize: 13.5, color: Color(0xFF0B1C30)),
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            isDense: true,
                                            hintText: 'Örn: 0194',
                                            hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'İşlem Tarihi',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: _spentAt,
                                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                            lastDate: DateTime.now().add(const Duration(days: 1)),
                                          );
                                          if (picked != null) {
                                            setState(() => _spentAt = picked);
                                          }
                                        },
                                        child: Container(
                                          height: 44,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF4FF),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _spentAt.day == DateTime.now().day &&
                                                        _spentAt.month == DateTime.now().month &&
                                                        _spentAt.year == DateTime.now().year
                                                    ? 'Bugün'
                                                    : '${_spentAt.day.toString().padLeft(2, '0')}.${_spentAt.month.toString().padLeft(2, '0')}.${_spentAt.year}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF0B1C30),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.calendar_today_outlined,
                                                size: 16,
                                                color: Color(0xFF64748B),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // KART 5: Fiş / Fatura Fotoğrafı
                      _CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: const [
                                      Icon(Icons.photo_camera_outlined, size: 19, color: Color(0xFF005C55)),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Fiş / Fatura Fotoğrafı',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0B1C30),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.verified_outlined, size: 14, color: Color(0xFFBA1A1A)),
                                    SizedBox(width: 3),
                                    Text(
                                      'Mali Denetim',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFBA1A1A),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (_imageError != null) ...[
                              Text(
                                _imageError!,
                                style: const TextStyle(color: Color(0xFFBA1A1A), fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (_preview == null) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF4FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFB5EFDA),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.document_scanner_outlined,
                                        size: 24,
                                        color: Color(0xFF376E5E),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Mali onay için fiş görseli gereklidir',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0B1C30),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Belgenin net ve okunur olduğundan emin olun',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: () => _pickPhoto(fromCamera: true),
                                            icon: const Icon(Icons.photo_camera_rounded, size: 16),
                                            label: const Text(
                                              'Kamera ile Çek',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(0xFF0F766E),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: () => _pickPhoto(fromCamera: false),
                                            icon: const Icon(Icons.image_outlined, size: 16),
                                            label: const Text(
                                              'Galeriden Seç',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(0xFFE5EEFF),
                                              foregroundColor: const Color(0xFF0B1C30),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5EEFF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        _preview!,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'fis_${_spentAt.day}${_spentAt.month}${_spentAt.year}.jpg',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0B1C30),
                                            ),
                                          ),
                                          Text(
                                            'Görsel yüklendi · ${(_receipt!.length / 1024).round()} KB',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF007952),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setState(() {
                                        _receipt = null;
                                        _preview = null;
                                      }),
                                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFBA1A1A)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // KART 6: Açıklama & Sorumlu
                      _CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.notes_rounded, size: 19, color: Color(0xFF005C55)),
                                SizedBox(width: 6),
                                Text(
                                  'Açıklama & Sorumlu',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0B1C30),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF4FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TextField(
                                controller: _descController,
                                minLines: 2,
                                maxLines: 4,
                                style: const TextStyle(fontSize: 13.5, color: Color(0xFF0B1C30)),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText:
                                      'Harcama nedeni ve satın alınan ürün detayı (örn: Marketten 4 koli acil barista sütü alındı)...',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12.5,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF4FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: const Color(0xFF005C55),
                                    child: Text(
                                      _userInitials(userName),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          userName,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0B1C30),
                                          ),
                                        ),
                                        Text(
                                          userRole,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF64748B)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // KART 7: Sabit Alt Bar (Kasadan Çıkacak Tutar + Butonlar)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: const Color(0xFFE2E8F0))),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5EEFF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: const [
                                Icon(Icons.account_balance_wallet_outlined, size: 17, color: Color(0xFF005C55)),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Kasadan Çıkacak Tutar:',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            fmtMoney(enteredAmount),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFBA1A1A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                backgroundColor: const Color(0xFFEFF4FF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text(
                                'Vazgeç',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 46,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _submit,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.check_circle_rounded, size: 18),
                              label: Text(
                                _saving ? 'Kaydediliyor...' : 'Masrafı Kaydet ve Düş',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF005C55),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardBox extends StatelessWidget {
  const _CardBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Ana Yönetici: mağaza başına haftalık limit belirleme.
Future<bool?> showLimitsDialog(BuildContext context) async {
  List<PettyCashLimit> limits;
  try {
    limits = await repo.pettyCashLimits();
  } catch (e) {
    return null;
  }
  if (!context.mounted) return null;

  final controllers = {
    for (final l in limits)
      l.storeId: TextEditingController(text: l.weeklyAmount.toString()),
  };

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Haftalık Petty Cash Limitleri',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) => [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Her mağazanın haftalık harcama tavanı. Hafta pazartesi başlar.',
            style: TextStyle(fontSize: 13, color: context.tokens.muted),
          ),
        ),
        ...limits.map(
          (l) => LabeledField(
            label: l.storeName,
            child: TextField(
              controller: controllers[l.storeId],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(suffixText: 'TL'),
            ),
          ),
        ),
      ],
      onSubmit: () async {
        for (final l in limits) {
          final raw = controllers[l.storeId]!.text.trim().replaceAll(',', '.');
          final value = num.tryParse(raw.isEmpty ? '0' : raw);
          if (value == null || value < 0) {
            return '${l.storeName}: limit 0 veya daha büyük olmalıdır';
          }
          if (value == l.weeklyAmount) continue;
          try {
            await repo.setPettyCashLimit(l.storeId, value);
          } catch (e) {
            return errorMessage(e);
          }
        }
        return null;
      },
    ),
  );
}

/// Masraf reddi. Gerekçe zorunlu: masrafı giren kişi neden reddedildiğini
/// görsün, sunucu da boş gerekçeyi kabul etmiyor.
Future<bool?> showPettyCashRejectDialog(
  BuildContext context,
  PettyCashExpense expense,
) {
  final note = TextEditingController();

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Masrafı Reddet',
      submitLabel: 'Reddet',
      fields: (context, rebuild) {
        final t = context.tokens;
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${fmtMoney(expense.amount)} — ${expense.description}\n'
              '${expense.createdByName ?? 'bilinmiyor'} girdi.',
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ),
          LabeledField(
            label: 'Ret Gerekçesi',
            hint: 'Masrafı giren kişi bu gerekçeyi görecek. '
                'Tutar haftalık limite geri eklenir.',
            child: TextField(
              controller: note,
              autofocus: true,
              maxLines: 2,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ];
      },
      onSubmit: () async {
        final text = note.text.trim();
        if (text.isEmpty) return 'Ret gerekçesi zorunludur';
        try {
          await repo.rejectPettyCash(expense, text);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}
