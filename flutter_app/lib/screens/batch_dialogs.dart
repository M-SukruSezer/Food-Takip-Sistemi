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
  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => _AddBatchSheet(types: types, stores: stores),
  );
}

class _AddBatchSheet extends StatefulWidget {
  const _AddBatchSheet({required this.types, required this.stores});

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
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
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
    showAppSheet<void>(
      context: context,
      builder: (ctx) {
        final tk = ctx.tokens;
        final text = Theme.of(ctx).textTheme;
        return StandardDialog(
          title: const Text('Ürün Çeşidi Seçin'),
          icon: Icons.cake_outlined,
          maxWidth: AppLayout.dialogMaxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final t in widget.types) ...[
                _ProductOption(
                  name: t.name,
                  detail: 'SKT: Çözünme Sonrası ${t.sktDays} Gün',
                  selected: t.id == _selectedTypeId,
                  tokens: tk,
                  text: text,
                  onTap: () {
                    setState(() => _selectedTypeId = t.id);
                    Navigator.of(ctx).pop();
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
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
    final t = context.tokens;
    final isSuper = session.user?.isSuperAdmin ?? false;
    final selectedProd = _selectedProduct;

    return StandardDialog(
      icon: Icons.ac_unit_rounded,
      busy: _submitting,
      maxWidth: AppLayout.dialogMaxWidth,
      title: Wrap(
        spacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Yeni Ürün Ekle'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.sm / 2),
            ),
            child: Text(
              'DONUK',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                fontWeight: FontWeight.w800,
                color: t.primary,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
      subtitle: 'Donuk depoya yeni parti ürün girişi yapın',
      footer: DialogActions(
        confirmLabel: 'Donuk Depoya Ekle',
        confirmIcon: Icons.check_rounded,
        busy: _submitting,
        onConfirm: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineError(_error!),
            const SizedBox(height: AppSpacing.md),
          ],

          // 1. Alan: Ürün Çeşidi
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ürün Çeşidi',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                  color: context.tokens.ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.tokens.successSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Tatlı & Pasta',
                  style: TextStyle(
                    fontSize: AppFontSize.micro,
                    fontWeight: FontWeight.w700,
                    color: context.tokens.primary,
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
                color: context.tokens.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.tokens.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: context.tokens.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.cake_outlined,
                      size: 16,
                      color: context.tokens.onPrimary,
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
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w700,
                            color: context.tokens.ink,
                          ),
                        ),
                        Text(
                          selectedProd != null
                              ? 'SKT: Çözünme Sonrası ${selectedProd.sktDays} Gün'
                              : 'Çeşit seçilmedi',
                          style: TextStyle(
                            fontSize: AppFontSize.micro,
                            fontWeight: FontWeight.w600,
                            color: context.tokens.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SEÇ',
                        style: TextStyle(
                          fontSize: AppFontSize.micro,
                          fontWeight: FontWeight.w700,
                          color: context.tokens.muted,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: context.tokens.muted,
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
                    Text(
                      'Adet / Kutu',
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        color: context.tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.tokens.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.tokens.border),
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
                                  color: context.tokens.card,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: context.tokens.border,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '-',
                                  style: TextStyle(
                                    fontSize: AppFontSize.title,
                                    fontWeight: FontWeight.w700,
                                    color: context.tokens.muted,
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
                              style: TextStyle(
                                fontSize: AppFontSize.bodyLarge,
                                fontWeight: FontWeight.w800,
                                color: context.tokens.ink,
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
                                  color: context.tokens.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '+',
                                  style: TextStyle(
                                    fontSize: AppFontSize.title,
                                    fontWeight: FontWeight.w700,
                                    color: context.tokens.onPrimary,
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
                      children: [
                        Text(
                          'Parti Kodu',
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w600,
                            color: context.tokens.ink,
                          ),
                        ),
                        Text(
                          'Oto No',
                          style: TextStyle(
                            fontSize: AppFontSize.micro,
                            color: context.tokens.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: context.tokens.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.tokens.border),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _codeController,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w600,
                                color: context.tokens.ink,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintText: 'PRT-2026-0929',
                                hintStyle: TextStyle(
                                  color: context.tokens.muted,
                                  fontSize: AppFontSize.label,
                                ),
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _scanBarcode,
                              child: Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 17,
                                  color: context.tokens.primary,
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
              color: context.tokens.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.tokens.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: context.tokens.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Giriş Rafı: ',
                                style: TextStyle(
                                  color: context.tokens.muted,
                                  fontSize: AppFontSize.caption,
                                ),
                              ),
                              TextSpan(
                                text: 'D-04 (Donuk 1)',
                                style: TextStyle(
                                  color: context.tokens.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.caption,
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
                  style: TextStyle(
                    color: context.tokens.muted,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          if (isSuper && widget.stores.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Mağaza (Ana Yönetici)',
              style: TextStyle(
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w600,
                color: context.tokens.ink,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.tokens.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.tokens.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _storeId,
                  isExpanded: true,
                  hint: const Text(
                    'Çeşidin kendi mağazası',
                    style: TextStyle(fontSize: AppFontSize.label),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text(
                        'Çeşidin kendi mağazası',
                        style: TextStyle(fontSize: AppFontSize.label),
                      ),
                    ),
                    ...widget.stores.map(
                      (s) => DropdownMenuItem<int?>(
                        value: s.id,
                        child: Text(
                          s.name,
                          style: const TextStyle(fontSize: AppFontSize.label),
                        ),
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
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Not ',
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        color: context.tokens.ink,
                      ),
                    ),
                    TextSpan(
                      text: '(opsiyonel)',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: context.tokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Maks. 120 krk',
                style: TextStyle(
                  fontSize: AppFontSize.micro,
                  color: context.tokens.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.tokens.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.tokens.border),
            ),
            child: TextField(
              controller: _notesController,
              maxLength: 120,
              minLines: 2,
              maxLines: 3,
              buildCounter: (
                _, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
              style: TextStyle(
                fontSize: AppFontSize.label,
                color: context.tokens.ink,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Tedarikçi teslimatı, hasar kontrolü veya saklama talimatı yazabilirsiniz...',
                hintStyle: TextStyle(
                  color: context.tokens.muted,
                  fontSize: AppFontSize.caption,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cozulme surecine alma. Kismi alinirsa parti bolunur.
Future<bool?> showThawDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: '${batch.remaining}');
  return showAppSheet<bool>(
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
            style: const TextStyle(fontSize: AppFontSize.title),
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
  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => _ZayiIkramSheet(batch: batch, initialIsIkram: isIkram),
  );
}

class _ZayiIkramSheet extends StatefulWidget {
  const _ZayiIkramSheet({required this.batch, this.initialIsIkram = false});

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
    (
      key: 'hasar',
      label: 'Düşürme / Fiziksel Hasar',
      icon: Icons.broken_image_rounded,
    ),
    (
      key: 'kalite',
      label: 'Tat / Kalite Bozukluğu',
      icon: Icons.sentiment_very_dissatisfied_rounded,
    ),
    (
      key: 'hazirlik',
      label: 'Personel Hatalı Hazırlık',
      icon: Icons.person_off_rounded,
    ),
    (
      key: 'vitrin',
      label: 'Vitrin / Teşhir Eskimesi',
      icon: Icons.storefront_rounded,
    ),
  ];

  static const _ikramReasons = [
    (
      key: 'memnuniyet',
      label: 'Müşteri Memnuniyeti / Jest',
      icon: Icons.sentiment_very_satisfied_rounded,
    ),
    (
      key: 'tadim',
      label: 'Tadım / Numune İkramı',
      icon: Icons.restaurant_rounded,
    ),
    (key: 'personel', label: 'Personel İkramı', icon: Icons.badge_rounded),
    (
      key: 'mudur',
      label: 'Müdür / Yönetici İnisiyatifi',
      icon: Icons.verified_user_rounded,
    ),
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
    final reasonLabel = reasons
        .firstWhere(
          (r) => r.key == _selectedReasonKey,
          orElse: () => reasons.first,
        )
        .label;

    final noteText = _notes.text.trim();
    final fullReason = noteText.isEmpty
        ? reasonLabel
        : '$reasonLabel: $noteText';

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
            successMessage:
                '${widget.batch.productName} — $_quantity adet ikram edildi',
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
          backgroundColor: context.tokens.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unitPrice = widget.batch.productUnitPrice ?? 0;
    final totalCost = _quantity * unitPrice;
    final formattedTotal = fmtMoney(totalCost);

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} $timeStr';

    final user = session.user;
    final fullName = user?.fullName.isNotEmpty == true
        ? user!.fullName
        : (user?.username ?? 'Personel');
    final initials = fullName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final roleName = switch (user?.role) {
      'super_admin' => 'Ana Yönetici',
      'operations_manager' => 'Operasyon Müdürü',
      'regional_manager' => 'Bölge Müdürü',
      'store_manager' => 'Mağaza Müdürü',
      'shift_supervisor' => 'Vardiya Müdürü',
      'barista' => 'Barista',
      _ => roleLabels[user?.role] ?? 'Personel',
    };
    final idStr = user?.id != null ? 'CLM-${user!.id}' : 'CLM-0000';

    final t = context.tokens;
    return StandardDialog(
      icon: Icons.report_gmailerrorred_rounded,
      iconColor: t.dangerText,
      title: const Text('Zayi & İkram Kayıt Formu'),
      subtitle: 'Kritik stok hareketi',
      busy: _saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTypeToggle(),
          const SizedBox(height: AppSpacing.md),
          _buildProductCard(unitPrice),
          const SizedBox(height: AppSpacing.md),
          _buildQuantityStepper(formattedTotal),
          const SizedBox(height: AppSpacing.md),
          _buildReasonSelector(),
          const SizedBox(height: AppSpacing.md),
          _buildCameraAndProof(timeStr),
          const SizedBox(height: AppSpacing.md),
          _buildNotesField(),
          const SizedBox(height: AppSpacing.md),
          _buildSignatureStamp(fullName, initials, roleName, idStr, dateStr),
          const SizedBox(height: AppSpacing.lg),
          _buildActionButtons(formattedTotal),
        ],
      ),
    );
  }

  Widget _buildTypeToggle() {
    final isZayi = _activeType == 'zayi';
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.tokens.bg,
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
                  color: isZayi ? context.tokens.card : Colors.transparent,
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
                      color: isZayi
                          ? context.tokens.danger
                          : context.tokens.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Zayi Çıkışı',
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.bold,
                        color: isZayi
                            ? context.tokens.danger
                            : context.tokens.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isZayi
                            ? context.tokens.danger
                            : context.tokens.border,
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
                  color: !isZayi ? context.tokens.card : Colors.transparent,
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
                      color: !isZayi
                          ? context.tokens.success
                          : context.tokens.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'İkram',
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.bold,
                        color: !isZayi
                            ? context.tokens.success
                            : context.tokens.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: !isZayi
                            ? context.tokens.success
                            : context.tokens.border,
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
        color: context.tokens.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SEÇİLİ VİTRİN ÜRÜNÜ',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  color: context.tokens.primary,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Değiştir',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color: context.tokens.primary,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 14,
                    color: context.tokens.primary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.batch.productName,
            style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.bold,
              color: context.tokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Birim: ',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  color: context.tokens.muted,
                ),
              ),
              Text(
                fmtMoney(unitPrice),
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.bold,
                  color: context.tokens.ink,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: context.tokens.muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Mevcut: ',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  color: context.tokens.muted,
                ),
              ),
              Text(
                '${widget.batch.remaining} Adet',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.bold,
                  color: context.tokens.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.batch.isExpired
                  ? context.tokens.dangerSoft
                  : context.tokens.warningSoft,
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
                        ? context.tokens.danger
                        : context.tokens.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  sktText,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: widget.batch.isExpired
                        ? context.tokens.danger
                        : context.tokens.warningText,
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
    final t = context.tokens;
    final maxQty = widget.batch.remaining > 0 ? widget.batch.remaining : 1;
    final isZayi = _activeType == 'zayi';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Sol blok kalan alanı kullanır; tutar uzarsa (ör. ₺12.345,00)
          // 320px telefonda sağdaki adet düğmelerini dışarı itmez.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ÇIKIŞ MİKTARI',
                  style: TextStyle(
                    fontSize: AppFontSize.micro,
                    fontWeight: FontWeight.w700,
                    color: context.tokens.muted,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_quantity Adet',
                  style: TextStyle(
                    fontSize: AppFontSize.titleLarge,
                    fontWeight: FontWeight.w800,
                    color: context.tokens.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Toplam Tutar: $formattedTotal',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: isZayi
                        ? context.tokens.danger
                        : context.tokens.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.tokens.bg,
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
                      color: _quantity > 1
                          ? context.tokens.card
                          : context.tokens.card.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      size: 20,
                      color: _quantity > 1
                          ? context.tokens.ink
                          : context.tokens.border,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFontSize.titleLarge,
                      fontWeight: FontWeight.w800,
                      color: context.tokens.primary,
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
                          ? context.tokens.primary
                          : context.tokens.primary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: context.tokens.onPrimary,
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
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.bold,
                    color: context.tokens.ink,
                  ),
                ),
                Text(
                  ' *',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.bold,
                    color: context.tokens.danger,
                  ),
                ),
              ],
            ),
            Text(
              'Zorunlu Seçim',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: context.tokens.muted,
              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? context.tokens.successSoft
                      : context.tokens.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: context.tokens.primary, width: 1.2)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      r.icon,
                      size: 20,
                      color: isSelected
                          ? context.tokens.primary
                          : context.tokens.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.label,
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? context.tokens.okText
                              : context.tokens.ink,
                        ),
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? context.tokens.primary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? null
                            : Border.all(
                                color: context.tokens.border,
                                width: 1.5,
                              ),
                      ),
                      alignment: Alignment.center,
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              size: 13,
                              color: context.tokens.onPrimary,
                            )
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
        color: context.tokens.bg,
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
                  Icon(
                    Icons.videocam_rounded,
                    size: 18,
                    color: context.tokens.primary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Kamera & Kasa Kaydı',
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.bold,
                      color: context.tokens.ink,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.tokens.infoSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'POS-01 ($timeStr)',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.bold,
                    color: context.tokens.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Material(
            color: context.tokens.card,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hasPhoto
                        ? context.tokens.success
                        : context.tokens.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _hasPhoto
                          ? Icons.check_circle
                          : Icons.photo_camera_rounded,
                      size: 22,
                      color: _hasPhoto
                          ? context.tokens.success
                          : context.tokens.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hasPhoto
                                ? 'Fotoğraf / Kanıt Eklendi ✓'
                                : 'Fotoğraf / Kanıt Ekle',
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.bold,
                              color: _hasPhoto
                                  ? context.tokens.okText
                                  : context.tokens.ink,
                            ),
                          ),
                          Text(
                            _hasPhoto
                                ? '1 görsel iliştirildi (kaldırmak için dokunun)'
                                : 'Tutanak veya ürün görseli (opsiyonel)',
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              color: context.tokens.muted,
                            ),
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
        Text(
          'Operasyonel Açıklama & Not',
          style: TextStyle(
            fontSize: AppFontSize.body,
            fontWeight: FontWeight.bold,
            color: context.tokens.ink,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.tokens.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.tokens.border),
          ),
          child: TextField(
            controller: _notes,
            maxLines: 2,
            style: TextStyle(
              fontSize: AppFontSize.body,
              color: context.tokens.ink,
            ),
            decoration: InputDecoration(
              hintText: 'Örn: Dolap sıcaklık dalgalanması sebebiyle krema formu bozulmuştur.',
              hintStyle: TextStyle(
                fontSize: AppFontSize.label,
                color: context.tokens.muted,
              ),
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
        color: context.tokens.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: context.tokens.primary,
            child: Text(
              initials,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.bold,
                color: context.tokens.onPrimary,
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
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.bold,
                    color: context.tokens.ink,
                  ),
                ),
                Text(
                  '$roleName · ID: $idStr',
                  style: TextStyle(
                    fontSize: AppFontSize.micro,
                    color: context.tokens.muted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'E-ONAY DAMGASI',
                style: TextStyle(
                  fontSize: AppFontSize.micro,
                  fontWeight: FontWeight.w800,
                  color: context.tokens.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.bold,
                  color: context.tokens.ink,
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
              backgroundColor: isZayi
                  ? context.tokens.primary
                  : context.tokens.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            icon: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.tokens.onPrimary,
                    ),
                  )
                : const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(
              label,
              style: const TextStyle(
                fontSize: AppFontSize.bodyLarge,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Vazgeç',
            style: TextStyle(
              fontSize: AppFontSize.bodyLarge,
              fontWeight: FontWeight.w600,
              color: context.tokens.muted,
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
  return showAppSheet<bool>(
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
            style: const TextStyle(fontSize: AppFontSize.title),
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
  return showAppSheet<bool>(
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
            style: const TextStyle(fontSize: AppFontSize.title),
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

  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Kaydı Düzelt — ${batch.productName}',
      titleWidget: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.circle,
                  size: 9,
                  color: context.tokens.primary,
                ),
              ),
            ),
            const TextSpan(text: 'Kaydı Düzelt — '),
            TextSpan(
              text: batch.productName,
              style: TextStyle(color: context.tokens.primaryDark),
            ),
          ],
        ),
      ),
      submitLabel: 'Düzeltmeyi Kaydet',
      submitColor: context.tokens.primary,
      fields: (context, rebuild) {
        final t = context.tokens;
        return [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 16,
                  color: context.tokens.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Yanlış girilen tarih/saat ve adetleri düzeltir. Ürünün durumu değişmez ve '
                    'yapılan düzeltme hareket kayıtlarına yazılır.',
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      color: t.muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FormRow(
            left: _QuantityCard(
              label: 'Toplam Adet',
              controller: quantity,
              minimum: 1,
              onChanged: rebuild,
            ),
            right: _QuantityCard(
              label: 'Kalan Adet',
              controller: remaining,
              minimum: 0,
              maximum: int.tryParse(quantity.text),
              onChanged: rebuild,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 12, color: t.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Kalan adet toplam adetten büyük olamaz.',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: t.muted,
                    ),
                  ),
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
              label: 'Food Dolabına Giriş · TETİKLEYİCİ TARİH',
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
              hint: batch.sktDays == null
                  ? 'Otomatik'
                  : 'Otomatik (+${batch.sktDays} Gün)',
              child: DateTimeField(value: sktEnd),
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

  await showAppSheet<void>(
    context: context,
    builder: (ctx) {
      final t = ctx.tokens;
      Widget row(
        String label,
        String value,
        IconData icon, {
        bool trigger = false,
        String? badge,
      }) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: trigger ? t.card : t.bg,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: trigger ? t.primary.withValues(alpha: .35) : t.border,
            width: trigger ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              trigger ? Icons.circle : icon,
              size: trigger ? 7 : 16,
              color: trigger ? t.primary : t.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 3,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: AppFontSize.label,
                    ),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: trigger
                            ? t.primarySoft
                            : t.border.withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: trigger ? t.primaryDark : t.muted,
                          fontSize: AppFontSize.micro,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: trigger ? t.primaryDark : t.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.caption,
                ),
              ),
            ),
          ],
        ),
      );
      return StandardDialog(
        title: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.circle, size: 9, color: t.primary),
                ),
              ),
              const TextSpan(text: 'Ürün Detayı — '),
              TextSpan(
                text: detail.productName,
                style: TextStyle(color: t.primaryDark),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        footer: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: t.primary,
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: () => Navigator.pop(ctx),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Kapat'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: t.primarySoft.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.primary.withValues(alpha: .18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: t.primarySoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: t.primary,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusLabels[detail.status] ?? detail.status,
                          style: TextStyle(
                            color: t.ink,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Mevcut Stok: ${detail.remaining} / ${detail.quantity} adet',
                          style: TextStyle(
                            color: t.muted,
                            fontSize: AppFontSize.micro,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (detail.sktDays != null)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: t.primary.withValues(alpha: .25),
                          ),
                        ),
                        child: Text(
                          '${detail.sktDays} Günlük Raf Ömrü',
                          style: TextStyle(
                            color: t.primaryDark,
                            fontSize: AppFontSize.micro,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            row(
              'Donuk Depoya Giriş',
              fmtDateTime(detail.enteredFrozenAt),
              Icons.calendar_today_outlined,
            ),
            if (detail.thawingStartedAt != null)
              row(
                'Çözülme Başlangıcı',
                fmtDateTime(detail.thawingStartedAt),
                Icons.schedule,
              ),
            if (detail.thawingFinishAt != null)
              row(
                'Çözülme Bitişi',
                fmtDateTime(detail.thawingFinishAt),
                Icons.schedule,
              ),
            if (detail.foodCabinetEnteredAt != null)
              row(
                'Food Dolabına Giriş',
                fmtDateTime(detail.foodCabinetEnteredAt),
                Icons.circle,
                trigger: true,
                badge: 'TETİKLEYİCİ TARİH',
              ),
            if (detail.sktEnd != null)
              row(
                'SKT Bitiş',
                fmtDateTime(detail.sktEnd),
                Icons.lock_outline,
                badge: detail.sktDays == null
                    ? 'Otomatik'
                    : 'Otomatik (+${detail.sktDays} Gün)',
              ),
            if (detail.notes?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(detail.notes!, style: TextStyle(color: t.muted)),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.assignment_outlined, color: t.muted, size: 15),
                const SizedBox(width: 6),
                Text(
                  'Satış Geçmişi',
                  style: TextStyle(
                    color: t.ink,
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${sales.length} İşlem',
                  style: TextStyle(color: t.muted, fontSize: AppFontSize.micro),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (sales.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Henüz satış yok',
                  style: TextStyle(color: t.muted),
                ),
              ),
            for (final sale in sales)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.bg,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        fmtDateTime(sale.soldAt),
                        style: TextStyle(
                          color: t.muted,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ),
                    Text(
                      '${sale.quantity} adet',
                      style: TextStyle(
                        color: t.muted,
                        fontSize: AppFontSize.micro,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      sale.unitPrice == null ? '—' : fmtMoney(sale.unitPrice),
                      style: TextStyle(
                        color: t.primaryDark,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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

  return showAppSheet<bool>(
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
              style: TextStyle(fontSize: AppFontSize.body, color: t.muted),
            ),
          ),
          LabeledField(
            label: 'Doğru Adet',
            hint: '0 yazarsanız ürün tamamen donuk depoya döner.',
            child: TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: AppFontSize.title),
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
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: t.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      onSubmit: () async {
        final n = int.tryParse(quantity.text.trim());
        if (n == null || n < 0) {
          return 'Doğru adet 0 veya daha büyük bir tam sayı olmalıdır';
        }
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

class _QuantityCard extends StatelessWidget {
  const _QuantityCard({
    required this.label,
    required this.controller,
    required this.minimum,
    required this.onChanged,
    this.maximum,
  });
  final String label;
  final TextEditingController controller;
  final int minimum;
  final int? maximum;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    void change(int delta) {
      final value = (int.tryParse(controller.text) ?? minimum) + delta;
      if (value < minimum || (maximum != null && value > maximum!)) return;
      controller.text = '$value';
      onChanged();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.ink,
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 36,
                height: 44,
                child: IconButton(
                  tooltip: '$label azalt',
                  padding: EdgeInsets.zero,
                  onPressed: () => change(-1),
                  icon: const Icon(Icons.remove, size: 19),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (_) => onChanged(),
                  style: const TextStyle(
                    fontSize: AppFontSize.headline,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                height: 44,
                child: IconButton(
                  tooltip: '$label artır',
                  padding: EdgeInsets.zero,
                  onPressed: () => change(1),
                  icon: const Icon(Icons.add, size: 19),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ürün seçim listesindeki tek satır. Seçili satır marka rengiyle vurgulanır;
/// renkler token'lardan geldiği için koyu temada da okunur.
class _ProductOption extends StatelessWidget {
  const _ProductOption({
    required this.name,
    required this.detail,
    required this.selected,
    required this.tokens,
    required this.text,
    required this.onTap,
  });

  final String name;
  final String detail;
  final bool selected;
  final AppTokens tokens;
  final TextTheme text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final accent = selected ? t.primary : t.ink;
    return Material(
      color: selected ? t.primarySoft : t.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: selected ? t.primary : t.border,
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 10,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? t.primary : t.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.cake_rounded,
                  size: 18,
                  color: selected ? t.onPrimary : t.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall!.copyWith(
                        color: selected ? t.primary : t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: t.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
