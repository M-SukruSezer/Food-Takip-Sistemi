import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/tokens.dart';
import 'standard_dialog.dart';
import '../models/batch.dart';

Future<bool?> showSellConfirmBottomSheet(BuildContext context, Batch b) {
  return showAppSheet<bool>(
    context: context,
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

    return StandardDialog(
      icon: Icons.point_of_sale,
      maxWidth: AppLayout.dialogMaxWidth,
      title: Wrap(
        spacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Satışı Onayla'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: successBg,
              borderRadius: BorderRadius.circular(AppRadius.sm / 2),
            ),
            child: Text(
              'KASA İŞLEMİ',
              style: Theme.of(context).textTheme.labelSmall!
                  .copyWith(fontWeight: FontWeight.w700, color: successText),
            ),
          ),
        ],
      ),
      subtitle: 'Stok düşümü ve ciro güncelleme',
      footer: DialogActions(
        confirmLabel: '1 Adet Satışı Yap',
        confirmIcon: Icons.check_circle,
        onConfirm: () => Navigator.pop(context, true),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textMain,
                  ),
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: outline),
                const SizedBox(height: 16),
                // Dar ekranda etiket ve adet çipleri alt satıra kayar;
                // önceki Row + Spacer 360px altında 160px taşıyordu.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Stok Değişimi:',
                          style: TextStyle(fontSize: 14, color: textMuted),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
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
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Birim Fiyat: ${batch.hasPrice ? fmtMoney(batch.productUnitPrice) : '0,00 ₺'}',
                            style: TextStyle(fontSize: 12, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '+${batch.hasPrice ? fmtMoney(batch.productUnitPrice) : '0,00 ₺'}',
                      style: TextStyle(
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
                        style: TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
