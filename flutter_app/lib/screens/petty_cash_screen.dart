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
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    await _load(silent: true);
  }

  Future<void> _showReceipt(PettyCashExpense e) async {
    String? data;
    try {
      data = await repo.pettyCashReceipt(e.id);
    } catch (_) {
      return;
    }
    if (!mounted || data == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '${fmtMoney(e.amount)} — ${e.description}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: InteractiveViewer(child: Image.memory(_decode(data!))),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Kapat'),
              ),
            ),
          ],
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
      addLabel: 'Masraf Ekle',
      onAdd: _canSpend ? _add : null,
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
                      style: TextStyle(fontSize: 13, color: t.muted),
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
            (e) => AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.description,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                      ),
                      Text(
                        fmtMoney(e.amount),
                        style: TextStyle(
                          fontSize: 15,
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
                      if (e.hasReceipt)
                        Pill(text: 'fişli', color: t.success)
                      else
                        Pill(text: 'fiş yok', color: t.muted),
                      if (_isSuper && e.storeName != null)
                        Pill(text: e.storeName!, color: t.primary),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${fmtDateTime(e.spentAt)} · ${e.createdByName ?? 'bilinmiyor'}',
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                  const SizedBox(height: 10),
                  CardActions(
                    children: [
                      OutlinedButton(
                        onPressed: e.hasReceipt ? () => _showReceipt(e) : null,
                        child: const Text('Fişi Gör'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.danger,
                          side: BorderSide(color: t.danger),
                        ),
                        onPressed: () => _delete(e),
                        child: const Text('Sil'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Haftalik limit durumu: harcanan / limit ve kalan.
class _LimitCard extends StatelessWidget {
  const _LimitCard({required this.status});

  final PettyCashStatus status;

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
    // Limitin %85'ini gecince uyari rengine doner.
    final tight = status.usedRatio >= 0.85;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bu Hafta',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              Text(
                '${fmtMoney(status.spentThisWeek)} / ${fmtMoney(status.weeklyLimit)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: status.usedRatio,
              minHeight: 10,
              backgroundColor: t.bg,
              valueColor: AlwaysStoppedAnimation<Color>(
                tight ? t.danger : t.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kalan: ${fmtMoney(status.remaining)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: tight ? t.danger : t.success,
            ),
          ),
          Text(
            'Hafta başlangıcı: ${fmtDate(status.weekStart)}',
            style: TextStyle(fontSize: 12, color: t.muted),
          ),
        ],
      ),
    );
  }
}
