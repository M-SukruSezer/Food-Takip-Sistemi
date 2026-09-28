import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/batch.dart';
import '../models/dashboard.dart';
import '../models/product_type.dart';
import '../widgets/dialogs.dart';

import 'qr_scan_screen.dart';

/// Donuk depoya yeni parti ekleme.
Future<bool?> showAddBatchDialog(
  BuildContext context, {
  required List<ProductType> types,
  required List<StoreOption> stores,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _AddBatchSheet(
      types: types,
      stores: stores,
    ),
  );
}

class _AddBatchSheet extends StatefulWidget {
  const _AddBatchSheet({
    required this.types,
    required this.stores,
  });

  final List<ProductType> types;
  final List<StoreOption> stores;

  @override
  State<_AddBatchSheet> createState() => _AddBatchSheetState();
}

class _AddBatchSheetState extends State<_AddBatchSheet> {
  int? _selectedTypeId;
  int? _storeId;
  late final TextEditingController _codeController;
  late final TextEditingController _qtyController;
  final _notesController = TextEditingController();
  int _quantity = 1;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedTypeId = widget.types.isNotEmpty ? widget.types.first.id : null;
    _codeController = TextEditingController(text: _defaultBatchCode());
    _qtyController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _defaultBatchCode() {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return 'PRT-$y-$m$d';
  }

  String _formatEntryTime() {
    final now = DateTime.now();
    const trMonths = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    final m = trMonths[now.month - 1];
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '${now.day} $m · $h:$min';
  }

  ProductType? get _selectedProduct {
    if (_selectedTypeId == null) return null;
    return widget.types.firstWhere(
      (t) => t.id == _selectedTypeId,
      orElse: () => widget.types.first,
    );
  }

  void _openProductSelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.65,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ürün Çeşidi Seçin',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: widget.types.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = widget.types[i];
                    final isSelected = t.id == _selectedTypeId;

                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _selectedTypeId = t.id);
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFF0FDFA) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.6 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFCCFBF1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.cake_rounded,
                                size: 18,
                                color: isSelected ? Colors.white : const Color(0xFF0F766E),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected ? const Color(0xFF0F766E) : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'SKT: Çözünme Sonrası ${t.sktDays} Gün',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isSelected ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF0F766E),
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scanBarcode() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanScreen(title: 'Parti Barkodu Okut'),
      ),
    );
    if (scanned != null && scanned.isNotEmpty) {
      setState(() => _codeController.text = scanned);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final qty = int.tryParse(_qtyController.text.trim()) ?? _quantity;
    if (_selectedTypeId == null) {
      setState(() => _error = 'Ürün çeşidi seçilmelidir');
      return;
    }
    if (qty < 1) {
      setState(() => _error = 'Miktar en az 1 olmalıdır');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await repo.createBatch(
        productTypeId: _selectedTypeId!,
        quantity: qty,
        storeId: _storeId,
        batchCode: _codeController.text.trim(),
        notes: _notesController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isSuper = session.user?.isSuperAdmin ?? false;
    final selectedProd = _selectedProduct;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sürükleme / Üst gösterge çubuğu
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),

                  // Modal Başlık Alanı
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 14, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFCCFBF1),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.ac_unit_rounded,
                            size: 20,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Yeni Ürün',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const Text(
                                    ' Ekle',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFCCFBF1),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Text(
                                      'DONUK',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F766E),
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Donuk depoya yeni parti ürün girişi yapın',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => Navigator.of(context).pop(false),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: Color(0xFFF1F5F9)),

                  // Form Gövdesi
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFB91C1C),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // 1. Alan: Ürün Çeşidi
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Ürün Çeşidi',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF334155),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDFA),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Tatlı & Pasta',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _openProductSelector,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F766E),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.cake_outlined,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedProd?.name.toUpperCase() ?? 'ÜRÜN SEÇİN',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        selectedProd != null
                                            ? 'SKT: Çözünme Sonrası ${selectedProd.sktDays} Gün'
                                            : 'Çeşit seçilmedi',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F766E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Text(
                                      'SEÇ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 2. Alan: Adet / Kutu & Parti Kodu (İki Kolon)
                        Row(
                          children: [
                            // Kolon 1: Adet Stepper
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Adet / Kutu',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: () {
                                              if (_quantity > 1) {
                                                setState(() {
                                                  _quantity--;
                                                  _qtyController.text = '$_quantity';
                                                });
                                              }
                                            },
                                            child: Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                              ),
                                              alignment: Alignment.center,
                                              child: const Text(
                                                '-',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: TextField(
                                            controller: _qtyController,
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF0F172A),
                                            ),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              isDense: true,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                            onChanged: (v) {
                                              final parsed = int.tryParse(v);
                                              if (parsed != null && parsed > 0) {
                                                _quantity = parsed;
                                              }
                                            },
                                          ),
                                        ),
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: () {
                                              setState(() {
                                                _quantity++;
                                                _qtyController.text = '$_quantity';
                                              });
                                            },
                                            child: Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF0F766E),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              alignment: Alignment.center,
                                              child: const Text(
                                                '+',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Kolon 2: Parti Kodu
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: const [
                                      Text(
                                        'Parti Kodu',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      Text(
                                        'Oto No',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 40,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _codeController,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0F172A),
                                            ),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              isDense: true,
                                              contentPadding: EdgeInsets.zero,
                                              hintText: 'PRT-2026-0929',
                                              hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                            ),
                                          ),
                                        ),
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(6),
                                            onTap: _scanBarcode,
                                            child: const Padding(
                                              padding: EdgeInsets.all(2),
                                              child: Icon(
                                                Icons.qr_code_scanner_rounded,
                                                size: 17,
                                                color: Color(0xFF0F766E),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // 3. Bilgi Şeridi: Giriş Rafı & Giriş Saati
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Giriş Rafı: ',
                                              style: TextStyle(
                                                color: Color(0xFF475569),
                                                fontSize: 11.5,
                                              ),
                                            ),
                                            TextSpan(
                                              text: 'D-04 (Donuk 1)',
                                              style: TextStyle(
                                                color: Color(0xFF0F172A),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11.5,
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
                              const SizedBox(width: 8),
                              Text(
                                _formatEntryTime(),
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (isSuper && widget.stores.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Mağaza (Ana Yönetici)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                value: _storeId,
                                isExpanded: true,
                                hint: const Text('Çeşidin kendi mağazası', style: TextStyle(fontSize: 12)),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('Çeşidin kendi mağazası', style: TextStyle(fontSize: 12)),
                                  ),
                                  ...widget.stores.map(
                                    (s) => DropdownMenuItem<int?>(
                                      value: s.id,
                                      child: Text(s.name, style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ],
                                onChanged: (v) => setState(() => _storeId = v),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // 4. Alan: Not (Opsiyonel)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Not ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                  TextSpan(
                                    text: '(opsiyonel)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Maks. 120 krk',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            controller: _notesController,
                            maxLength: 120,
                            minLines: 2,
                            maxLines: 3,
                            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A)),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Tedarikçi teslimatı, hasar kontrolü veya saklama talimatı yazabilirsiniz...',
                              hintStyle: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 5. Aksiyon Butonları (Vazgeç & Donuk Depoya Ekle)
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton(
                                  onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF334155),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text(
                                    'Vazgeç',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 44,
                                child: FilledButton.icon(
                                  onPressed: _submitting ? null : _submit,
                                  icon: _submitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Icon(Icons.check_rounded, size: 18),
                                  label: Text(
                                    _submitting ? 'Kaydediliyor...' : 'Donuk Depoya Ekle',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F766E),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shadowColor: const Color(0xFF0F766E).withValues(alpha: 0.3),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        ),
      ),
    );
  }
}

/// Cozulme surecine alma. Kismi alinirsa parti bolunur.
Future<bool?> showThawDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: '${batch.remaining}');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Çözülmeye Al',
      submitLabel: 'Çözülmeye Al',
      fields: (context, rebuild) => [
        Text(
          '${batch.productName} — kalan ${batch.remaining} adet',
          style: TextStyle(color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Adet',
          hint: 'Tamamı alınmazsa parti bölünür, kalan donukta durur. Süre +4°C, 8 saat.',
          child: TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        if (qty == null || qty < 1) return 'Miktar en az 1 olmalıdır';
        if (qty > batch.remaining) {
            return 'Yeterli stok yok. Kalan: ${batch.remaining}';
          }
        try {
          await repo.thaw(batch.id, qty);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Zayi: adet ve sebep.
Future<bool?> showDiscardDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: '${batch.remaining}');
  final reason = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Zayi Gir',
      submitLabel: 'Zayi Gir',
      fields: (context, rebuild) => [
        Text(
          '${batch.productName} — kalan ${batch.remaining} adet',
          style: TextStyle(color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Adet',
          child: TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        LabeledField(
          label: 'Sebep',
          child: TextField(
            controller: reason,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        if (qty == null || qty < 1) return 'Miktar en az 1 olmalıdır';
        if (qty > batch.remaining) {
            return 'Yeterli stok yok. Kalan: ${batch.remaining}';
          }
        try {
          await repo.discard(
            batch.id,
            quantity: qty,
            reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
          );
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Donuk stoka adet ekleme.
Future<bool?> showStockAddDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: '1');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Stok Ekle',
      submitLabel: 'Stoka Ekle',
      fields: (context, rebuild) => [
        Text(
          '${batch.productName} — mevcut ${batch.remaining} adet',
          style: TextStyle(color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Eklenecek Adet',
          child: TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        if (qty == null || qty < 1) return 'Miktar en az 1 olmalıdır';
        try {
          await repo.addStock(batch.id, qty);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Sure dolmadan food dolabina aktarim icin yonetici onayi istegi.
Future<bool?> showEarlyRequestDialog(BuildContext context, Batch batch) {
  final reason = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Erken Aktarım İste',
      submitLabel: 'Onaya Gönder',
      fields: (context, rebuild) => [
        Text(
          '${batch.productName} (${batch.remaining} adet) çözünme süresi dolmadan food dolabına '
          'alınmak isteniyor. Kalan süre: ${formatHours(batch.thawRemainingHours)}.',
          style: TextStyle(color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Erken Aktarım Nedeni',
          child: TextField(
            controller: reason,
            maxLines: 3,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'örn: Müşteri siparişi için acil ihtiyaç var',
            ),
          ),
        ),
      ],
      onSubmit: () async {
        if (reason.text.trim().length < 3) {
            return 'Erken aktarım nedeni yazılmalıdır';
          }
        try {
          await repo.requestEarlyTransfer(batch.id, reason.text.trim());
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Ana Yonetici duzeltmesi: tarih/saat ve adetler.
Future<bool?> showAdjustDialog(BuildContext context, Batch batch) {
  DateTime? parse(String? iso) =>
      iso == null ? null : DateTime.tryParse(iso)?.toLocal();

  final quantity = TextEditingController(text: '${batch.quantity}');
  final remaining = TextEditingController(text: '${batch.remaining}');
  var frozenAt = parse(batch.enteredFrozenAt);
  var thawStart = parse(batch.thawingStartedAt);
  var thawFinish = parse(batch.thawingFinishAt);
  var cabinetAt = parse(batch.foodCabinetEnteredAt);
  var sktEnd = parse(batch.sktEnd);

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Kaydı Düzelt — ${batch.productName}',
      submitLabel: 'Düzeltmeyi Kaydet',
      fields: (context, rebuild) => [
        Text(
          'Yanlış girilen tarih/saat ve adetleri düzeltir. Ürünün durumu değişmez ve '
          'yapılan düzeltme hareket kayıtlarına yazılır.',
          style: TextStyle(fontSize: 13, color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        FormRow(
          left: LabeledField(
            label: 'Toplam Adet',
            child: TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          right: LabeledField(
            label: 'Kalan Adet',
            child: TextField(
              controller: remaining,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Kalan adet toplam adetten büyük olamaz.',
            style: TextStyle(fontSize: 11, color: context.tokens.muted),
          ),
        ),
        LabeledField(
          label: 'Donuk Depoya Giriş',
          child: DateTimeField(
            value: frozenAt,
            onChanged: (v) {
              frozenAt = v;
              rebuild();
            },
          ),
        ),
        if (thawStart != null)
          LabeledField(
            label: 'Çözülme Başlangıcı',
            child: DateTimeField(
              value: thawStart,
              onChanged: (v) {
                thawStart = v;
                rebuild();
              },
            ),
          ),
        if (thawFinish != null)
          LabeledField(
            label: 'Çözülme Bitişi',
            child: DateTimeField(
              value: thawFinish,
              onChanged: (v) {
                thawFinish = v;
                rebuild();
              },
            ),
          ),
        if (cabinetAt != null)
          LabeledField(
            label: 'Food Dolabına Giriş',
            hint: batch.sktDays == null
                ? null
                : 'Bu tarih değişince SKT bitişi ${batch.sktDays} güne göre yeniden hesaplanır.',
            child: DateTimeField(
              value: cabinetAt,
              onChanged: (v) {
                cabinetAt = v;
                // SKT, dugmeye basildigi an degil dolaba giris anina gore hesaplanir.
                if (batch.sktDays != null) {
                  sktEnd = v.add(Duration(days: batch.sktDays!));
                }
                rebuild();
              },
            ),
          ),
        if (sktEnd != null)
          LabeledField(
            label: 'SKT Bitiş',
            child: DateTimeField(
              value: sktEnd,
              onChanged: (v) {
                sktEnd = v;
                rebuild();
              },
            ),
          ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        final rem = int.tryParse(remaining.text.trim());
        if (qty == null || qty < 1) return 'Toplam adet en az 1 olmalıdır';
        if (rem == null || rem < 0) {
            return 'Kalan adet 0 veya daha büyük olmalıdır';
          }
        if (rem > qty) {
            return 'Kalan adet toplam adetten büyük olamaz (toplam: $qty)';
          }
        if (frozenAt == null) return 'Donuk depoya giriş tarihi zorunludur';

        String? iso(DateTime? d) => d?.toUtc().toIso8601String();
        try {
          await repo.adjustBatch(batch.id, {
            'quantity': qty,
            'remaining': rem,
            'entered_frozen_at': iso(frozenAt),
            if (thawStart != null) 'thawing_started_at': iso(thawStart),
            if (thawFinish != null) 'thawing_finish_at': iso(thawFinish),
            if (cabinetAt != null) 'food_cabinet_entered_at': iso(cabinetAt),
            if (sktEnd != null) 'skt_end': iso(sktEnd),
          });
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Parti detayi ve satis gecmisi.
Future<void> showBatchDetail(BuildContext context, Batch batch) async {
  List<SaleRecord> sales = const [];
  Batch detail = batch;
  try {
    final (b, s) = await repo.batchDetail(batch.id);
    detail = b;
    sales = s;
  } catch (_) {
    // Bildirim API katmaninda gosterilir; eldeki ozet yine gosterilir.
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = ctx.tokens;
      Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: t.muted),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
          ],
        ),
      );

      return AlertDialog(
        title: Text('Ürün Detayı — ${detail.productName}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                row('Durum', statusLabels[detail.status] ?? detail.status),
                row('Miktar', '${detail.remaining} / ${detail.quantity} adet'),
                row('Donuk Depoya Giriş', fmtDateTime(detail.enteredFrozenAt)),
                if (detail.thawingStartedAt != null)
                  row(
                    'Çözülme Başlangıcı',
                    fmtDateTime(detail.thawingStartedAt),
                  ),
                if (detail.thawingFinishAt != null)
                  row('Çözülme Bitişi', fmtDateTime(detail.thawingFinishAt)),
                if (detail.foodCabinetEnteredAt != null)
                  row(
                    'Food Dolabına Giriş',
                    fmtDateTime(detail.foodCabinetEnteredAt),
                  ),
                if (detail.sktEnd != null)
                  row('SKT Bitiş', fmtDateTime(detail.sktEnd)),
                if (detail.notes != null && detail.notes!.isNotEmpty)
                  row('Not', detail.notes!),
                const SizedBox(height: 12),
                Text(
                  'Satış Geçmişi',
                  style: TextStyle(fontWeight: FontWeight.w700, color: t.ink),
                ),
                const SizedBox(height: 8),
                if (sales.isEmpty)
                  Text(
                    'Henüz satış yok',
                    style: TextStyle(color: t.muted, fontSize: 13),
                  )
                else
                  ...sales.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              fmtDateTime(s.soldAt),
                              style: TextStyle(fontSize: 13, color: t.ink),
                            ),
                          ),
                          Text(
                            '${s.quantity} adet',
                            style: TextStyle(fontSize: 13, color: t.muted),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            s.unitPrice == null ? '-' : fmtMoney(s.unitPrice),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      );
    },
  );
}

/// Cozulmeye alinan adedi duzeltir.
///
/// Kullanici "dogru adet kaci" girer; fark donuk depoya geri doner. 0 girilirse
/// parti cozulmeden tamamen cikar. Fark once ayni partiden bolunmus donuk
/// kardese eklenir, yoksa donma tarihi korunarak yeni donuk parti acilir.
Future<bool?> showCorrectThawDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: batch.remaining.toString());

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Çözülme Adedini Düzelt',
      submitLabel: 'Düzelt',
      fields: (context, rebuild) {
        final t = context.tokens;
        final entered = int.tryParse(quantity.text.trim());
        final back = entered == null || entered < 0 || entered > batch.remaining
            ? null
            : batch.remaining - entered;
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${batch.productName} — şu anda ${batch.remaining} adet çözülmede.',
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ),
          LabeledField(
            label: 'Doğru Adet',
            hint: '0 yazarsanız ürün tamamen donuk depoya döner.',
            child: TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
              onChanged: (_) => rebuild(),
            ),
          ),
          if (back != null && back > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.ac_unit, size: 18, color: t.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$back adet donuk depoya geri dönecek. '
                      'Dondurucuya giriş tarihi korunur.',
                      style: TextStyle(fontSize: 12, color: t.ink),
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      onSubmit: () async {
        final n = int.tryParse(quantity.text.trim());
        if (n == null || n < 0) return 'Doğru adet 0 veya daha büyük bir tam sayı olmalıdır';
        if (n > batch.remaining) {
          return 'Doğru adet mevcut adetten (${batch.remaining}) büyük olamaz';
        }
        if (n == batch.remaining) return 'Adet değişmedi';
        try {
          await repo.correctThawQuantity(batch, n);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

