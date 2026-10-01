import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/tokens.dart';
import '../models/batch.dart';

Future<bool?> showSellConfirmBottomSheet(BuildContext context, Batch b) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SellConfirmBottomSheet(batch: b),
  );
}

class _SellConfirmBottomSheet extends StatelessWidget {
  final Batch batch;
  const _SellConfirmBottomSheet({required this.batch});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final Color surface = t.card;
    final Color primary = t.primary;
    final Color onPrimary = t.onPrimary;
    final Color outline = t.border;
    final Color textMain = t.ink;
    final Color textMuted = t.muted;
    final Color warningBg = t.warningSoft;
    final Color warningText = t.warningText;
    final Color warningDot = t.warning;
    final Color successBg = t.successSoft;
    final Color successText = t.success;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(left: 24, right: 24, top: 12, bottom: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: successBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.point_of_sale, color: primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Satışı Onayla',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: textMain,
                            letterSpacing: -0.01,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: successBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'KASA İŞLEMİ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: successText,
                              letterSpacing: 0.05,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Stok düşümü ve ciro güncelleme',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context, false),
                icon: Icon(Icons.close, color: textMuted),
                style: IconButton.styleFrom(
                  backgroundColor: t.bg,
                  shape: const CircleBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Product Details Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: outline),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'FIRIN & TATLI GRUBU',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: primary,
                        letterSpacing: 0.05,
                      ),
                    ),
                    if (batch.urgency == 'soon')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: warningBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: warningDot,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'SON GÜN',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: warningText,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  batch.productName,
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textMain,
                  ),
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: outline),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Stok Değişimi:',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: textMuted,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: surface,
                        border: Border.all(color: outline),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${batch.remaining} Adet',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: successBg,
                        border: Border.all(
                          color: t.success.withValues(alpha: .45),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${batch.remaining - 1} Adet Kalan',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Revenue Details Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary.withValues(alpha: .35)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet,
                        color: onPrimary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ciroya Eklenecek Tutar',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Birim Fiyat: ${batch.hasPrice ? fmtMoney(batch.productUnitPrice) : '0,00 ₺'}',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '+${batch.hasPrice ? fmtMoney(batch.productUnitPrice) : '0,00 ₺'}',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: textMain,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.verified, size: 16, color: primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kasa raporuna ve anlık gün sonu cirosuna hemen işlenir.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: outline, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    foregroundColor: textMain,
                  ),
                  child: const Text(
                    'Vazgeç',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: const Text(
                    '1 Adet Satışı Yap',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
