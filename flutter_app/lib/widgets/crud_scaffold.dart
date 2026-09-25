import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'panels.dart';

/// Kart izgarasinin kolon sayisi. Esikler CSS'teki kirilma noktalariyla ayni:
/// 640 telefon, 900 tablet, 1200 genis masaustu. Tablet dikeyde (768) iki kolon
/// kullanilir; uc kolonda kart basina ~225px kaliyor ve etiketler siksiyor.
int gridColumnsFor(double width) {
  if (width < 641) return 1;
  if (width < 900) return 2;
  if (width < 1200) return 3;
  return 4;
}

/// Uc CRUD ekrani (Cesitler, Magazalar, Kullanicilar) ayni iskeleti paylasir:
/// baslik + ekle dugmesi, opsiyonel uyari, hata cikisi, kart listesi.
class CrudScaffold extends StatelessWidget {
  const CrudScaffold({
    super.key,
    required this.title,
    required this.loaded,
    required this.error,
    required this.onRetry,
    required this.onRefresh,
    required this.children,
    this.addLabel,
    this.onAdd,
    this.banner,
    this.emptyText,
    this.grid = false,
  });

  final String title;
  final bool loaded;
  final String? error;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final String? addLabel;
  final VoidCallback? onAdd;
  final Widget? banner;
  final String? emptyText;

  /// Kart izgarasi (Cesitler, Magazalar) ya da tek kolon liste (Kullanicilar).
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final columns = gridColumnsFor(MediaQuery.sizeOf(context).width);

    if (!loaded) return const SizedBox.shrink();
    if (error != null && children.isEmpty) {
      return Center(
        child: AppCard(
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
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ),
                if (onAdd != null)
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(addLabel ?? 'Yeni'),
                  ),
              ],
            ),
          ),
          if (banner != null) ...[
            const SizedBox(height: AppTokens.gap),
            banner!,
          ],
          const SizedBox(height: AppTokens.gap),
          if (children.isEmpty)
            AppCard(
              child: Text(
                emptyText ?? 'Kayıt bulunamadı.',
                style: TextStyle(color: t.muted),
              ),
            )
          else if (grid && columns > 1)
            // Sabit en-boy oranli izgara kart icerigini kesiyordu (uzun urun
            // adi ya da iki satirlik aciklamada tasma). Bunun yerine her satir
            // IntrinsicHeight ile kendi icerigi kadar yukseliyor; ayni satirdaki
            // kartlar birbirine esit kaliyor.
            Column(
              children: [
                for (
                  var start = 0;
                  start < children.length;
                  start += columns
                ) ...[
                  if (start > 0) const SizedBox(height: AppTokens.gap),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < columns; col++) ...[
                          if (col > 0) const SizedBox(width: AppTokens.gap),
                          Expanded(
                            child: start + col < children.length
                                ? children[start + col]
                                // Son satirdaki bosluklar kartlarin genisligini
                                // bozmasin diye yer tutucu konur.
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppTokens.gap),
                  children[i],
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// Kart icinde kucuk etiket (React'teki .pill).
class Pill extends StatelessWidget {
  const Pill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Kart alt satirinda Duzenle / Sil gibi islemler.
class CardActions extends StatelessWidget {
  const CardActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}
