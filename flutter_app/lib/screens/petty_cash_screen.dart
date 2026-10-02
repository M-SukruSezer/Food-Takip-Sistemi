import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/petty_cash.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import 'petty_cash_dialogs.dart';
import '../widgets/panels.dart';
import '../widgets/swipe_actions.dart';

/// Petty Cash: magaza kasasindan yapilan kucuk masraflar.
///
/// Masraf girisi yalnizca Store Manager ve Shift Supervisor'da; haftalik limit
/// Ana Yonetici tarafindan magaza basina belirlenir. Ust kademeler (Ana
/// Yonetici, Operations/Regional Manager) sorumlu olduklari magazalarin
/// kayitlarini gorur ama giris yapamaz.
class PettyCashScreen extends StatefulWidget {
  const PettyCashScreen({super.key});

  @override
  State<PettyCashScreen> createState() => _PettyCashScreenState();
}

class _PettyCashScreenState extends State<PettyCashScreen> {
  PettyCashPage _page = const PettyCashPage(items: []);
  String? _error;
  bool _loaded = false;

  static const _spenderRoles = ['store_manager', 'shift_supervisor'];

  bool get _canSpend => _spenderRoles.contains(session.user?.role);
  bool get _isSuper => session.user?.isSuperAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final page = await repo.pettyCash(silent: silent);
      if (!mounted) return;
      setState(() {
        _page = page;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loaded = true;
      });
    }
  }

  Future<void> _add() async {
    final ok = await showExpenseDialog(context, status: _page.status);
    if (ok == true) {
      toastSaved('Masraf kaydedildi');
      await _load(silent: true);
    }
  }

  Future<void> _edit(PettyCashExpense e) async {
    final ok = await showExpenseDialog(
      context,
      status: _page.status,
      expense: e,
    );
    if (ok == true) {
      toastSaved('Masraf güncellendi');
      await _load(silent: true);
    }
  }

  /// Bekleyen kaydi giren kisi; karar tasiyan kaydi yalnizca Ana Yonetici
  /// duzenler/siler (sunucudaki kuralin aynisi).
  bool _canModify(PettyCashExpense e) =>
      _isSuper || (e.isPending && e.createdBy == session.user?.id);

  Future<void> _approve(PettyCashExpense e) async {
    final ok = await confirmDialog(
      context,
      title: 'Masrafı Onayla',
      danger: false,
      confirmLabel: 'Onayla',
      body: Text(
        '${fmtMoney(e.amount)} — ${e.description}\n'
        '${e.createdByName ?? 'bilinmiyor'} girdi.'
        '${e.hasReceipt ? '' : '\n\nBu masrafta fiş görseli yok.'}',
      ),
    );
    if (ok != true) return;
    try {
      await repo.approvePettyCash(e);
    } catch (err) {
      if (mounted) toastError(errorMessage(err));
      return;
    }
    await _load(silent: true);
  }

  Future<void> _reject(PettyCashExpense e) async {
    final ok = await showPettyCashRejectDialog(context, e);
    if (ok == true) await _load(silent: true);
  }

  Future<void> _delete(PettyCashExpense e) async {
    final ok = await confirmDialog(
      context,
      title: 'Masrafı Sil',
      confirmLabel: 'Sil',
      body: Text(
        '${fmtMoney(e.amount)} — ${e.description}\n\nBu kayıt silinecek.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.deletePettyCash(e);
    } catch (err) {
      if (mounted) toastError(errorMessage(err));
      return;
    }
    await _load(silent: true);
  }

  Future<void> _showReceipt(PettyCashExpense e) async {
    String? data;
    try {
      data = await repo.pettyCashReceipt(e.id);
    } catch (err) {
      if (mounted) toastError(errorMessage(err));
      return;
    }
    if (!mounted || data == null) return;
    await showAppSheet<void>(
      context: context,
      builder: (ctx) => StandardDialog(
        title: const Text('Fiş'),
        subtitle: '${fmtMoney(e.amount)} — ${e.description}',
        icon: Icons.receipt_long_outlined,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InteractiveViewer(child: Image.memory(_decode(data!))),
        ),
      ),
    );
  }

  static Uint8List _decode(String dataUrl) =>
      base64Decode(dataUrl.split(',').last);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = _page.status;

    return CrudScaffold(
      title: 'Petty Cash',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      floatingActions: [
        if (_canSpend)
          FloatingActionButton.extended(
            heroTag: null,
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Masraf Ekle'),
          ),
      ],
      emptyText: 'Bu hafta masraf kaydı yok.',
      banner: Column(
        children: [
          if (status != null) _LimitCard(status: status),
          if (_isSuper) ...[
            if (status != null) const SizedBox(height: AppTokens.gap),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mağazaların haftalık limitlerini buradan belirleyin.',
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        color: t.muted,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final changed = await showLimitsDialog(context);
                      if (changed == true) await _load(silent: true);
                    },
                    child: const Text('Limitler'),
                  ),
                ],
              ),
            ),
          ],
          if (!_canSpend && !_isSuper) ...[
            if (status != null) const SizedBox(height: AppTokens.gap),
            AppAlert(
              danger: false,
              icon: Icons.info_outline,
              message:
                  'Masraf girişi yalnızca Store Manager ve Shift Supervisor '
                  'kullanıcılarına açıktır; buradan kayıtları görüntüleyebilirsiniz.',
            ),
          ],
        ],
      ),
      children: _page.items
          .map(
            (e) => SwipeActions(
              actions: [
                if (_canModify(e))
                  SwipeAction(
                    label: 'Düzenle',
                    icon: Icons.edit_outlined,
                    color: t.primary,
                    onTap: () => _edit(e),
                  ),
                if (_canModify(e))
                  SwipeAction(
                    label: 'Sil',
                    icon: Icons.delete_outline,
                    color: t.danger,
                    onTap: () => _delete(e),
                  ),
              ],
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            splitExpenseDescription(e.description).text,
                            style: TextStyle(
                              fontSize: AppFontSize.bodyLarge,
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                          ),
                        ),
                        Text(
                          fmtMoney(e.amount),
                          style: TextStyle(
                            fontSize: AppFontSize.bodyLarge,
                            fontWeight: FontWeight.w700,
                            color: t.danger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // Vardiya muduru girisi magaza muduru onayina takilir.
                        Pill(
                          text: e.statusLabel,
                          color: e.isPending
                              ? t.warning
                              : e.isRejected
                              ? t.danger
                              : t.success,
                        ),
                        if (splitExpenseDescription(e.description).category
                            case final c?)
                          Pill(text: c, color: t.primary),
                        if (e.hasReceipt)
                          Pill(text: 'fişli', color: t.success)
                        else
                          Pill(text: 'fiş yok', color: t.muted),
                        if (_isSuper && e.storeName != null)
                          Pill(text: e.storeName!, color: t.primary),
                      ],
                    ),
                    if (e.isRejected && e.decisionNote != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Ret gerekçesi: ${e.decisionNote}',
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          color: t.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${fmtDateTime(e.spentAt)} · ${e.createdByName ?? 'bilinmiyor'}',
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: t.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    CardActions(
                      children: [
                        OutlinedButton(
                          onPressed: e.hasReceipt
                              ? () => _showReceipt(e)
                              : null,
                          child: const Text('Fişi Gör'),
                        ),
                        if (e.isPending &&
                            (_page.status?.canApprove ?? false)) ...[
                          FilledButton(
                            onPressed: () => _approve(e),
                            child: const Text('Onayla'),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.danger,
                              side: BorderSide(color: t.danger),
                            ),
                            onPressed: () => _reject(e),
                            child: const Text('Reddet'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Haftalık kasa limiti ve bakiye: limit, kalan bakiye, harcanan/kalan
/// oranını gösteren iki renkli çubuk ve haftanın tarih aralığı.
class _LimitCard extends StatelessWidget {
  const _LimitCard({required this.status});

  final PettyCashStatus status;

  String _weekRange() {
    final start = DateTime.tryParse(status.weekStart)?.toLocal();
    if (start == null) return '';
    final end = start.add(const Duration(days: 6));
    String d(DateTime v) =>
        '${v.day.toString().padLeft(2, '0')}.${v.month.toString().padLeft(2, '0')}';
    return '${d(start)} – ${d(end)}.${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!status.hasLimit) {
      return AppAlert(
        message:
            'Bu mağaza için haftalık petty cash limiti tanımlanmamış. '
            'Masraf girilebilmesi için Ana Yöneticinin limit belirlemesi gerekir.',
      );
    }
    final ratio = status.usedRatio.clamp(0.0, 1.0);
    TextStyle small() => TextStyle(
      fontSize: AppFontSize.caption,
      fontWeight: FontWeight.w500,
      color: t.muted,
    );
    TextStyle big(Color c) => TextStyle(
      fontSize: AppFontSize.title,
      fontWeight: FontWeight.w800,
      color: c,
      letterSpacing: -0.3,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Haftalık Kasa Limiti', style: small()),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        fmtMoney(status.weeklyLimit),
                        style: big(t.ink),
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
                    Text('Mevcut Bakiye', style: small()),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        fmtMoney(status.remaining),
                        style: big(ratio >= 0.85 ? t.danger : t.success),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Iki renkli cubuk: kirmizi harcanan, yesil kalan.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (ratio > 0)
                    Expanded(
                      flex: (ratio * 1000).round(),
                      child: ColoredBox(color: t.danger),
                    ),
                  if (ratio < 1)
                    Expanded(
                      flex: ((1 - ratio) * 1000).round(),
                      child: ColoredBox(color: t.success),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: t.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Bu Hafta: ', style: small()),
                      TextSpan(
                        text: fmtMoney(status.spentThisWeek),
                        style: small().copyWith(
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text('Hafta: ${_weekRange()}', style: small()),
            ],
          ),
          // Bekleyen masraf da limitten dusuyor: para kasadan cikti.
          if (status.pendingThisWeek > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${fmtMoney(status.pendingThisWeek)} onay bekliyor '
              '(${status.pendingCount} kayıt)',
              style: TextStyle(fontSize: AppFontSize.label, color: t.warning),
            ),
          ],
        ],
      ),
    );
  }
}
