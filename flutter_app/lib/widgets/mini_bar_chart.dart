import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/tokens.dart';

/// 7 gunluk cubuk grafik. fl_chart yerine elle cizildi: yalnizca yedi cubuk
/// gerektigi icin ek paket yuku ve tema uyumu derdi olmuyor.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.label,
    required this.values,
    required this.dates,
    required this.barColor,
    this.showAsMoney = false,
  });

  final String label;
  final List<num> values;
  final List<String> dates;
  final Color barColor;
  final bool showAsMoney;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final narrow = MediaQuery.sizeOf(context).width < 641;
    final max = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b);
    final safeMax = max <= 0 ? 1 : max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: narrow ? 132 : 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(values.length, (i) {
              final v = values[i];
              final ratio = (v / safeMax).clamp(0.04, 1).toDouble();
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        showAsMoney ? v.round().toString() : '${v.round()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Grafik ekseni: React tarafinda da 11px taban
                        // (10px magazada telefonda okunmuyordu).
                        style: TextStyle(
                          fontSize: 11,
                          color: t.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: FractionallySizedBox(
                          alignment: Alignment.bottomCenter,
                          heightFactor: ratio,
                          child: Container(
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dates.length > i
                            ? fmtDate(dates[i]).substring(0, 5)
                            : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: t.muted),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
