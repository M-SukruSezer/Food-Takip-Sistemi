import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/opts.dart';
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

/// Zayi: adet ve sebep - modern Zayi & İkram Kayıt Formu.
Future<bool?> showDiscardDialog(
  BuildContext context,
  Batch batch, {
  bool isIkram = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _ZayiIkramSheet(batch: batch, initialIsIkram: isIkram),
  );
}

class _ZayiIkramSheet extends StatefulWidget {
  const _ZayiIkramSheet({
    required this.batch,
    this.initialIsIkram = false,
  });

  final Batch batch;
  final bool initialIsIkram;

  @override
  State<_ZayiIkramSheet> createState() => _ZayiIkramSheetState();
}

class _ZayiIkramSheetState extends State<_ZayiIkramSheet> {
  late String _activeType; // 'zayi' or 'ikram'
  late int _quantity;
  late String _selectedReasonKey;
  final TextEditingController _notes = TextEditingController();
  bool _hasPhoto = false;
  bool _saving = false;

  static const _zayiReasons = [
    (key: 'skt', label: 'SKT Dolumu / Bozulma', icon: Icons.event_busy_rounded),
    (key: 'hasar', label: 'Düşürme / Fiziksel Hasar', icon: Icons.broken_image_rounded),
    (key: 'kalite', label: 'Tat / Kalite Bozukluğu', icon: Icons.sentiment_very_dissatisfied_rounded),
    (key: 'hazirlik', label: 'Personel Hatalı Hazırlık', icon: Icons.person_off_rounded),
    (key: 'vitrin', label: 'Vitrin / Teşhir Eskimesi', icon: Icons.storefront_rounded),
  ];

  static const _ikramReasons = [
    (key: 'memnuniyet', label: 'Müşteri Memnuniyeti / Jest', icon: Icons.sentiment_very_satisfied_rounded),
    (key: 'tadim', label: 'Tadım / Numune İkramı', icon: Icons.restaurant_rounded),
    (key: 'personel', label: 'Personel İkramı', icon: Icons.badge_rounded),
    (key: 'mudur', label: 'Müdür / Yönetici İnisiyatifi', icon: Icons.verified_user_rounded),
    (key: 'diger', label: 'Diğer / Tanıtım', icon: Icons.card_giftcard_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _activeType = widget.initialIsIkram ? 'ikram' : 'zayi';
    _quantity = widget.batch.remaining > 0 ? widget.batch.remaining : 1;
    _selectedReasonKey = _activeType == 'zayi' ? 'skt' : 'memnuniyet';
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);

    final reasons = _activeType == 'zayi' ? _zayiReasons : _ikramReasons;
    final reasonLabel = reasons.firstWhere(
      (r) => r.key == _selectedReasonKey,
      orElse: () => reasons.first,
    ).label;

    final noteText = _notes.text.trim();
    final fullReason = noteText.isEmpty ? reasonLabel : '$reasonLabel: $noteText';

    try {
      if (_activeType == 'zayi') {
        await repo.discard(
          widget.batch.id,
          quantity: _quantity,
          reason: fullReason,
        );
      } else {
        await api.dio.post(
          '/batches/${widget.batch.id}/sell',
          data: {'quantity': _quantity, 'kind': 'ikram'},
          options: apiOptions(
            successMessage: '${widget.batch.productName} — $_quantity adet ikram edildi',
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage(e)),
          backgroundColor: const Color(0xFFBA1A1A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxH = mediaQuery.size.height * 0.92;

    final unitPrice = widget.batch.productUnitPrice ?? 0;
    final totalCost = _quantity * unitPrice;
    final formattedTotal = fmtMoney(totalCost);

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} $timeStr';

    final user = session.user;
    final fullName = user?.fullName.isNotEmpty == true ? user!.fullName : 'Muhammed Şükrü Sezer';
    final initials = fullName.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final roleName = switch (user?.role) {
      'super_admin' => 'Ana Yönetici',
      'operations_manager' => 'Operasyon Müdürü',
      'regional_manager' => 'Bölge Müdürü',
      'store_manager' => 'Store Manager',
      'shift_supervisor' => 'Vardiya Müdürü',
      'barista' => 'Barista',
      _ => 'Store Manager',
    };
    final idStr = 'CLM-${user?.id ?? 8492}';

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFFBA1A1A),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'KRİTİK STOK HAREKETİ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFBA1A1A),
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Zayi & İkram Kayıt Formu',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0B1C30),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(false),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFF4FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 18, color: Color(0xFF0B1C30)),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Transaction Type Toggle (Zayi / İkram)
                    _buildTypeToggle(),
                    const SizedBox(height: 12),

                    // 2. Selected Product Card
                    _buildProductCard(unitPrice),
                    const SizedBox(height: 12),

                    // 3. Quantity Stepper & Cost Computation
                    _buildQuantityStepper(formattedTotal),
                    const SizedBox(height: 12),

                    // 4. Reason Selector
                    _buildReasonSelector(),
                    const SizedBox(height: 12),

                    // 5. Camera & Proof Card
                    _buildCameraAndProof(timeStr),
                    const SizedBox(height: 12),

                    // 6. Notes Field
                    _buildNotesField(),
                    const SizedBox(height: 12),

                    // 7. Authorization & E-Signature Strip
                    _buildSignatureStamp(fullName, initials, roleName, idStr, dateStr),
                    const SizedBox(height: 16),

                    // 8. Action Buttons
                    _buildActionButtons(formattedTotal),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    final isZayi = _activeType == 'zayi';
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Tab 1: Zayi Çıkışı
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isZayi) {
                  setState(() {
                    _activeType = 'zayi';
                    _selectedReasonKey = 'skt';
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isZayi ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isZayi
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.delete_forever_rounded,
                      size: 18,
                      color: isZayi ? const Color(0xFFBA1A1A) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Zayi Çıkışı',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: isZayi ? const Color(0xFFBA1A1A) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isZayi ? const Color(0xFFBA1A1A) : const Color(0xFFBDC9C6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tab 2: İkram
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isZayi) {
                  setState(() {
                    _activeType = 'ikram';
                    _selectedReasonKey = 'memnuniyet';
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !isZayi ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: !isZayi
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.redeem_rounded,
                      size: 18,
                      color: !isZayi ? const Color(0xFF007952) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'İkram',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: !isZayi ? const Color(0xFF007952) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: !isZayi ? const Color(0xFF007952) : const Color(0xFFBDC9C6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(num unitPrice) {
    final sktText = widget.batch.sktEnd == null
        ? 'SKT Belirtilmemiş'
        : widget.batch.isExpired
            ? 'SKT: ${fmtDate(widget.batch.sktEnd)} (${widget.batch.daysLeft != null ? widget.batch.daysLeft!.abs() : 1} gün geçti)'
            : 'SKT: ${fmtDate(widget.batch.sktEnd)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'SEÇİLİ VİTRİN ÜRÜNÜ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F766E),
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Değiştir',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.swap_horiz_rounded, size: 14, color: Color(0xFF0F766E)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.batch.productName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0B1C30),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Birim: ',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              Text(
                fmtMoney(unitPrice),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0B1C30),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 3,
                height: 3,
                decoration: const BoxDecoration(
                  color: Color(0xFF64748B),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Mevcut: ',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              Text(
                '${widget.batch.remaining} Adet',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0B1C30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.batch.isExpired
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.batch.isExpired
                        ? const Color(0xFFBA1A1A)
                        : const Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  sktText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.batch.isExpired
                        ? const Color(0xFF93000A)
                        : const Color(0xFF92400E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityStepper(String formattedTotal) {
    final maxQty = widget.batch.remaining > 0 ? widget.batch.remaining : 1;
    final isZayi = _activeType == 'zayi';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ÇIKIŞ MİKTARI',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$_quantity Adet',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B1C30),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Toplam Tutar: $formattedTotal',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isZayi ? const Color(0xFFBA1A1A) : const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _quantity > 1
                      ? () => setState(() => _quantity -= 1)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _quantity > 1 ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      size: 20,
                      color: _quantity > 1 ? const Color(0xFF0B1C30) : const Color(0xFFBDC9C6),
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _quantity < maxQty
                      ? () => setState(() => _quantity += 1)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _quantity < maxQty
                          ? const Color(0xFF0F766E)
                          : const Color(0xFF0F766E).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonSelector() {
    final isZayi = _activeType == 'zayi';
    final reasons = isZayi ? _zayiReasons : _ikramReasons;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  isZayi ? 'Zayi / İptal Nedeni' : 'İkram Nedeni',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0B1C30),
                  ),
                ),
                const Text(
                  ' *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFBA1A1A),
                  ),
                ),
              ],
            ),
            const Text(
              'Zorunlu Seçim',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...reasons.map((r) {
          final isSelected = _selectedReasonKey == r.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: () => setState(() => _selectedReasonKey = r.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFD1FAE5) : const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: const Color(0xFF0F766E), width: 1.2)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      r.icon,
                      size: 20,
                      color: isSelected ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFF065F46) : const Color(0xFF0B1C30),
                        ),
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0F766E) : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? null
                            : Border.all(color: const Color(0xFFBDC9C6), width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: isSelected
                          ? const Icon(Icons.check, size: 13, color: Colors.white)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCameraAndProof(String timeStr) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.videocam_rounded, size: 18, color: Color(0xFF0F766E)),
                  SizedBox(width: 6),
                  Text(
                    'Kamera & Kasa Kaydı',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0B1C30),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCE9FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'POS-01 ($timeStr)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                setState(() => _hasPhoto = !_hasPhoto);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _hasPhoto
                          ? 'Fotoğraf kanıtı eklendi.'
                          : 'Fotoğraf kanıtı kaldırıldı.',
                    ),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hasPhoto ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _hasPhoto ? Icons.check_circle : Icons.photo_camera_rounded,
                      size: 22,
                      color: _hasPhoto ? const Color(0xFF10B981) : const Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hasPhoto ? 'Fotoğraf / Kanıt Eklendi ✓' : 'Fotoğraf / Kanıt Ekle',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _hasPhoto ? const Color(0xFF065F46) : const Color(0xFF0B1C30),
                            ),
                          ),
                          Text(
                            _hasPhoto ? '1 görsel iliştirildi (kaldırmak için dokunun)' : 'Tutanak veya ürün görseli (opsiyonel)',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operasyonel Açıklama & Not',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0B1C30),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _notes,
            maxLines: 2,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF0B1C30)),
            decoration: const InputDecoration(
              hintText: 'Örn: Dolap sıcaklık dalgalanması sebebiyle krema formu bozulmuştur.',
              hintStyle: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureStamp(
    String fullName,
    String initials,
    String roleName,
    String idStr,
    String dateStr,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF0F766E),
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
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
                  fullName,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0B1C30),
                  ),
                ),
                Text(
                  '$roleName · ID: $idStr',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'E-ONAY DAMGASI',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F766E),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0B1C30),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(String formattedTotal) {
    final isZayi = _activeType == 'zayi';
    final label = isZayi
        ? 'Zayi Kaydını Onayla ($formattedTotal)'
        : 'İkramı Onayla ($formattedTotal)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: isZayi ? const Color(0xFF005C55) : const Color(0xFF007952),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Vazgeç',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }
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
      headerIcon: Icons.edit_note_rounded,
      subtitle: '• Parti Bilgilerini Güncelle',
      submitLabel: 'Düzeltmeyi Kaydet',
      submitColor: const Color(0xFF0F766E),
      fields: (context, rebuild) {
        final t = context.tokens;
        return [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 16,
                  color: Color(0xFF0F766E),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Yanlış girilen tarih/saat ve adetleri düzeltir. Ürünün durumu değişmez ve '
                    'yapılan düzeltme hareket kayıtlarına yazılır.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.muted,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FormRow(
            left: LabeledField(
              label: 'Toplam Adet',
              child: Container(
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.border.withValues(alpha: 0.7)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      onPressed: () {
                        final v = int.tryParse(quantity.text.trim()) ?? 1;
                        if (v > 1) {
                          quantity.text = (v - 1).toString();
                          rebuild();
                        }
                      },
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      color: t.muted,
                    ),
                    Expanded(
                      child: TextField(
                        controller: quantity,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: () {
                        final v = int.tryParse(quantity.text.trim()) ?? 0;
                        quantity.text = (v + 1).toString();
                        rebuild();
                      },
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      color: const Color(0xFF0F766E),
                    ),
                  ],
                ),
              ),
            ),
            right: LabeledField(
              label: 'Kalan Adet',
              child: Container(
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.border.withValues(alpha: 0.7)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      onPressed: () {
                        final v = int.tryParse(remaining.text.trim()) ?? 0;
                        if (v > 0) {
                          remaining.text = (v - 1).toString();
                          rebuild();
                        }
                      },
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      color: t.muted,
                    ),
                    Expanded(
                      child: TextField(
                        controller: remaining,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: () {
                        final v = int.tryParse(remaining.text.trim()) ?? 0;
                        final max = int.tryParse(quantity.text.trim()) ?? 999;
                        if (v < max) {
                          remaining.text = (v + 1).toString();
                          rebuild();
                        }
                      },
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      color: const Color(0xFF0F766E),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 12, color: t.muted),
                const SizedBox(width: 4),
                Text(
                  'Kalan adet toplam adetten büyük olamaz.',
                  style: TextStyle(fontSize: 11, color: t.muted),
                ),
              ],
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
              hint: '🔒 Otomatik (+3 Gün)',
              child: DateTimeField(
                value: sktEnd,
                onChanged: (v) {
                  sktEnd = v;
                  rebuild();
                },
              ),
            ),
        ];
      },
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
      final screen = MediaQuery.sizeOf(ctx);
      final narrow = screen.width < 600;

      Widget timelineItem({
        required String label,
        required String value,
        String? badge,
      }) {
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 16,
                color: const Color(0xFF0F766E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.muted,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCCFBF1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.fromLTRB(
          narrow ? 16 : 24,
          narrow ? 16 : 22,
          narrow ? 16 : 24,
          0,
        ),
        contentPadding: EdgeInsets.fromLTRB(
          narrow ? 16 : 24,
          12,
          narrow ? 16 : 24,
          0,
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: Color(0xFF0F766E),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ürün Detayı — ${detail.productName}',
                    style: TextStyle(
                      fontSize: narrow ? 16 : 18,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '• Parti #${detail.id} Özeti',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () => Navigator.pop(ctx),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: t.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.border.withValues(alpha: 0.6)),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: t.muted,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: narrow ? screen.width - 64 : 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top status summary card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Icon(
                          Icons.inventory_2_rounded,
                          color: Color(0xFF0F766E),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  statusLabels[detail.status] ?? detail.status,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: t.muted,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD1FAE5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Aktif',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF065F46),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Mevcut Stok: ${detail.remaining} / ${detail.quantity} adet',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: t.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCCFBF1)),
                        ),
                        child: Text(
                          '${detail.sktDays ?? 3} Günlük Raf Ömrü',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Timeline / Lifecycle cards
                timelineItem(
                  label: 'Donuk Depoya Giriş',
                  value: fmtDateTime(detail.enteredFrozenAt),
                ),
                if (detail.thawingStartedAt != null)
                  timelineItem(
                    label: 'Çözülme Başlangıcı',
                    value: fmtDateTime(detail.thawingStartedAt),
                  ),
                if (detail.thawingFinishAt != null)
                  timelineItem(
                    label: 'Çözülme Bitişi',
                    value: fmtDateTime(detail.thawingFinishAt),
                  ),
                if (detail.foodCabinetEnteredAt != null)
                  timelineItem(
                    label: 'Food Dolabına Giriş',
                    value: fmtDateTime(detail.foodCabinetEnteredAt),
                    badge: 'TETİKLEYİCİ TARİH',
                  ),
                if (detail.sktEnd != null)
                  timelineItem(
                    label: 'SKT Bitiş',
                    value: fmtDateTime(detail.sktEnd),
                    badge: 'Otomatik (+3 Gün)',
                  ),
                if (detail.notes != null && detail.notes!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.border.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes_rounded, size: 16, color: t.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Not',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: t.muted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                detail.notes!,
                                style: TextStyle(fontSize: 13, color: t.ink),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                // Satış Geçmişi Section
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      size: 16,
                      color: Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Satış Geçmişi',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFBF1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        sales.isEmpty ? 'Kayıt Yok' : '${sales.length} İşlem',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (sales.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.border.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      'Henüz satış yok',
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                  )
                else
                  ...sales.map(
                    (s) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: t.border.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              fmtDateTime(s.soldAt),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${s.quantity} adet',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFA7F3D0),
                              ),
                            ),
                            child: Text(
                              s.unitPrice == null ? '-' : fmtMoney(s.unitPrice),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F766E),
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
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                '✓ Kapat',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
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

