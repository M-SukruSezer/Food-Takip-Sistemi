import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/tokens.dart';
import '../models/daily_report.dart';
import '../models/manager_overview.dart';
import '../widgets/panels.dart';

/// Ana sayfadaki genel rapor. Yalnizca magaza muduru ve vardiya muduru gorur.
///
/// Sira istenen gibi: 1) Ciro Forecast, 2) Petty Cash. Ikisi de tiklanabilir
/// ve ilgili modulu acar. Stok yeterliligi ana sayfada cok yer kapladigi icin
/// kendi moduluna tasindi (/stock-coverage).
class ManagerOverviewBlock extends StatelessWidget {
  const ManagerOverviewBlock({
    super.key,
    required this.overview,
    required this.fields,
  });

  final ManagerOverview overview;
  final ReportFields fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaceCard(revenue: overview.revenue, fields: fields),
        const SizedBox(height: AppTokens.gap),
        _PettyCashCard(status: overview.pettyCash),
      ],
    );
  }
}

/// Karti tiklanabilir yapar; dokunuldugunda verilen yola gider.
class _TapCard extends StatelessWidget {
  const _TapCard({required this.to, required this.child});

  final String to;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radius),
      onTap: () => context.go(to),
      child: child,
    );
  }
}

Widget _heading(BuildContext context, String title, String? subtitle) {
  final t = context.tokens;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 12, color: t.muted)),
            ],
          ],
        ),
      ),
      // Kartin tiklanabilir oldugunu belli eder.
      Icon(Icons.chevron_right, size: 20, color: t.muted),
    ],
  );
}

/// Haftalik petty cash limiti: harcanan, kalan ve doluluk cubugu.
class _PettyCashCard extends StatelessWidget {
  const _PettyCashCard({required this.status});

  final PettyCashStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pct = status.usedPct;
    // Limit asildiginda cubuk tasmasin; renk zaten uyari veriyor.
    final fill = pct == null ? 0.0 : pct.clamp(0.0, 1.0).toDouble();
    final barColor = status.overLimit
        ? t.danger
        : fill >= 0.8
        ? t.warning
        : t.success;

    return _TapCard(
      to: '/petty-cash',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(
              context,
              'Petty Cash',
              status.limitSet
                  ? 'Haftalık limit · ${status.expenseCount} masraf kaydı'
                  : 'Haftalık limit tanımlanmamış',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Harcanan',
                    value: fmtMoney(status.spentThisWeek),
                    color: status.overLimit ? t.danger : t.ink,
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Kalan',
                    value: status.limitSet ? fmtMoney(status.remaining) : '-',
                    color: t.success,
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Limit',
                    value: status.limitSet ? fmtMoney(status.weeklyLimit) : '-',
                    color: t.muted,
                  ),
                ),
              ],
            ),
            if (status.limitSet) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fill,
                  minHeight: 8,
                  backgroundColor: t.border,
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                status.overLimit
                    ? 'Limit aşıldı: ${fmtMoney(status.spentThisWeek - status.weeklyLimit)} fazla'
                    : '${((pct ?? 0) * 100).toStringAsFixed(0)}% kullanıldı',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status.overLimit ? t.danger : t.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ciro hizi, ay sonu tahmini ve rapor paneli olculeri.
class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.revenue, required this.fields});

  final RevenuePace revenue;
  final ReportFields fields;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasData = revenue.daysWithData > 0;

    return _TapCard(
      to: '/daily-report',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(
              context,
              'Ciro Forecast',
              'Ay başından bugüne ${revenue.daysWithData} günün raporu girildi'
                  '${revenue.daysMissing > 0 ? ' · ${revenue.daysMissing} gün eksik' : ''}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Ay başından bu yana',
                    value: fmtMoney(revenue.mtdNetSales),
                    color: t.ink,
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Günlük ortalama',
                    value: hasData ? fmtMoney(revenue.dailyAvg) : '-',
                    color: t.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_up, size: 20, color: t.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ay sonu tahmini',
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasData
                              ? fmtMoney(revenue.forecastMonthEnd)
                              : 'Veri girilmedi',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: t.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasData)
                    Text(
                      '${revenue.remainingDays} gün kaldı',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                ],
              ),
            ),
            if (hasData) ...[
              const SizedBox(height: 6),
              Text(
                'Günlük ortalama, rapor girilmiş ${revenue.daysWithData} güne bölünerek '
                'hesaplanır; eksik günler sıfır sayılmaz.',
                style: TextStyle(fontSize: 11, color: t.muted),
              ),
            ],
            if (hasData && fields.derived.isNotEmpty) ...[
              const Divider(height: 22),
              Text(
                'Rapor Paneli — Bu Ay',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fields.derived
                    .map(
                      (f) => _Chip(
                        label: f.label,
                        value: _fmt(revenue.monthMetrics[f.key], f.type),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _fmt(num? v, String type) {
  if (v == null) return '-';
  return switch (type) {
    'money' => fmtMoney(v),
    'percent' => '${(v * 100).toStringAsFixed(2)}%',
    'int' => fmtInt(v),
    _ => v.toStringAsFixed(2),
  };
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: t.muted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: TextStyle(fontSize: 11, color: t.muted)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
        ],
      ),
    );
  }
}
