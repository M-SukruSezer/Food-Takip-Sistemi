import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/approval.dart';
import '../models/dashboard.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';

/// Erken aktarim onaylari: cozulme suresi (8 saat) dolmadan food dolabina
/// alinmak istenen partiler. Onay verildiginde SKT onay aninda baslar.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  static const _filters = {
    'pending': 'Bekleyenler',
    '': 'Tümü',
    'approved': 'Onaylananlar',
    'rejected': 'Reddedilenler',
    'cancelled': 'İptal Edilenler',
  };

  List<TransferApproval> _items = const [];
  List<StoreOption> _stores = const [];
  String _filter = 'pending';
  int? _storeId;
  String? _error;
  bool _loaded = false;

  bool get _isSuper => session.user?.isSuperAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _load();
    if (_isSuper) {
      repo.stores(silent: true).then((s) {
        if (mounted) setState(() => _stores = s);
      }).onError((Object _, StackTrace _) {});
    }
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.approvals(
        status: _filter.isEmpty ? null : _filter,
        storeId: _storeId,
        silent: silent,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _approve(TransferApproval item) async {
    final ok = await confirmDialog(
      context,
      danger: false,
      title: 'Erken Aktarımı Onayla',
      confirmLabel: 'Onayla',
      body: Text(
        '${item.productName ?? 'Ürün'} (${item.remaining} adet) food dolabına alınacak. '
        'SKT süresi şu andan itibaren başlar'
        '${item.thawRemainingHours != null && item.thawRemainingHours! > 0 ? ', çözülmeye ${formatHours(item.thawRemainingHours)} kalmıştı' : ''}.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.approveTransfer(item);
    } catch (_) {
      // Bildirim API katmanindan gelir; liste yine yenilenir cunku sunucu
      // istegi "artik cozulmede degil" diyerek iptal etmis olabilir.
    }
    await _load(silent: true);
  }

  Future<void> _reject(TransferApproval item) async {
    final ok = await showRejectDialog(context, item);
    if (ok == true) {
      toastSaved('İstek reddedildi, ürün çözülmede kaldı');
      await _load(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pending = _items.where((i) => i.pending).length;

    return CrudScaffold(
      title: 'Erken Aktarım Onayları',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      emptyText: 'Kayıt bulunamadı.',
      banner: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _filter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Durum'),
                  items: _filters.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _filter = v ?? 'pending');
                    _load(silent: true);
                  },
                ),
                if (_isSuper && _stores.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.gap),
                  DropdownButtonFormField<int?>(
                    initialValue: _storeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Mağaza'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Tüm Mağazalar')),
                      ..._stores.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))),
                    ],
                    onChanged: (v) {
                      setState(() => _storeId = v);
                      _load(silent: true);
                    },
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Çözünme süresi (8 saat) dolmadan food dolabına alınmak istenen ürünler burada '
                  'onaylanır. Onaylanan ürünün SKT süresi onay anından itibaren başlar.',
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
              ],
            ),
          ),
          if (pending > 0) ...[
            const SizedBox(height: AppTokens.gap),
            AppAlert(
              danger: false,
              icon: Icons.pending_actions,
              message: '$pending bekleyen istek var.',
            ),
          ],
        ],
      ),
      children: _items
          .map((item) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(item.productName ?? 'Ürün',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700, color: t.ink)),
                        ),
                        Pill(text: item.statusLabel, color: _statusColor(item.status, t)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(item.reason.isEmpty ? 'Neden yazılmamış' : item.reason,
                        style: TextStyle(fontSize: 14, color: t.ink)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(text: '${item.remaining} adet', color: t.info),
                        if (item.thawRemainingHours != null)
                          Pill(
                            text: 'çözülmeye ${formatHours(item.thawRemainingHours)}',
                            color: t.warning,
                          ),
                        if (_isSuper && item.storeName != null)
                          Pill(text: item.storeName!, color: t.primary),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${fmtDateTime(item.requestedAt)} · ${item.requestedByName ?? 'bilinmiyor'} istedi',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                    if (!item.pending && (item.decidedByName != null || item.decisionNote != null))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (item.decidedByName != null) '${item.decidedByName} karar verdi',
                            if (item.decisionNote?.isNotEmpty == true) item.decisionNote!,
                          ].join(' — '),
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                      ),
                    if (item.pending) ...[
                      const SizedBox(height: 10),
                      CardActions(children: [
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: t.success),
                          onPressed: () => _approve(item),
                          child: const Text('Onayla'),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.danger,
                            side: BorderSide(color: t.danger),
                          ),
                          onPressed: () => _reject(item),
                          child: const Text('Reddet'),
                        ),
                      ]),
                    ],
                  ],
                ),
              ))
          .toList(),
    );
  }

  Color _statusColor(String status, AppTokens t) {
    switch (status) {
      case 'approved':
        return t.success;
      case 'rejected':
        return t.danger;
      case 'cancelled':
        return t.muted;
      default:
        return t.warning;
    }
  }
}

/// Red penceresi. Not opsiyonel; girilirse hareket kaydina yazilir.
Future<bool?> showRejectDialog(BuildContext context, TransferApproval item) {
  final note = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'İsteği Reddet',
      submitLabel: 'Reddet',
      fields: (context, rebuild) => [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${item.productName ?? 'Ürün'} (${item.remaining} adet) çözülme sürecinde kalacak.',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        LabeledField(
          label: 'Red Nedeni (opsiyonel)',
          child: TextField(
            controller: note,
            maxLines: 2,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'örn: Çözülme tamamlanmadan alınamaz',
            ),
          ),
        ),
      ],
      onSubmit: () async {
        try {
          await repo.rejectTransfer(item, note.text.trim().isEmpty ? null : note.text.trim());
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}
