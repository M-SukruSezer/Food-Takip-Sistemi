import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/dashboard.dart';

enum RankTone { up, down, waste }

/// Urun performansi siralamasi: ad, oransal cubuk, adet.
class RankList extends StatelessWidget {
  const RankList({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
    required this.tone,
    required this.emptyText,
  });

  final String title;
  final IconData icon;
  final List<ProductRank> rows;
  final RankTone tone;
  final String emptyText;

  Color _barColor(AppTokens t) => switch (tone) {
        RankTone.up => t.success,
        RankTone.down => t.warning,
        RankTone.waste => t.danger,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final max = rows.isEmpty ? 1 : rows.map((r) => r.qty).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: t.muted),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: t.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Text(emptyText, style: TextStyle(color: t.muted, fontSize: 13))
        else
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: t.ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: max == 0 ? 0 : (r.qty / max).clamp(0.06, 1).toDouble(),
                          minHeight: 7,
                          backgroundColor: t.bg,
                          valueColor: AlwaysStoppedAnimation<Color>(_barColor(t)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${r.qty}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}
