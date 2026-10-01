import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/activity_log.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/panels.dart';

/// Islem koduna gore ikon. Listede olmayan kodlar genel ikon alir.
IconData logIcon(String action) {
  const map = {
    'GIRIS': Icons.vpn_key_outlined,
    'MAGAZA_OLUSTUR': Icons.store_outlined,
    'MAGAZA_GUNCELLE': Icons.store_outlined,
    'MAGAZA_SIL': Icons.store_outlined,
    'KULLANICI_OLUSTUR': Icons.person_outline,
    'KULLANICI_GUNCELLE': Icons.person_outline,
    'KULLANICI_SIL': Icons.person_outline,
    'SIFRE_SIFIRLA': Icons.lock_outline,
    'SIFRE_DEGISTIR': Icons.lock_outline,
    'CESIT_OLUSTUR': Icons.cake_outlined,
    'CESIT_GUNCELLE': Icons.cake_outlined,
    'CESIT_SIL': Icons.cake_outlined,
    'DONUK_EKLE': Icons.ac_unit,
    'COZULME_BASLA': Icons.hourglass_bottom,
    'FOOD_DOLABI': Icons.kitchen_outlined,
    'FOOD_DOLABI_OTOMATIK': Icons.kitchen_outlined,
    'SATIS': Icons.payments_outlined,
    'IMHA': Icons.delete_outline,
    'STOK_EKLE': Icons.add_box_outlined,
    'PARTI_DUZELT': Icons.edit_calendar_outlined,
    // Geriye donuk adet duzeltmeleri ve silmeler.
    'COZULME_DUZELT': Icons.undo,
    'SATIS_DUZELT': Icons.edit_outlined,
    'SATIS_SIL': Icons.delete_forever_outlined,
    'ZAYI_DUZELT': Icons.edit_outlined,
    'ZAYI_SIL': Icons.delete_forever_outlined,
    'PARTI_SIL': Icons.delete_forever_outlined,
    'TRANSFER_ISTEK': Icons.fact_check_outlined,
    'TRANSFER_ONAY': Icons.check_circle_outline,
    'TRANSFER_RET': Icons.cancel_outlined,
    'TRANSFER_IPTAL': Icons.cancel_outlined,
  };
  return map[action] ?? Icons.receipt_long_outlined;
}

/// Hareket kayitlari: son 300 islem, islem koduna gore filtreli.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<ActivityLog> _items = const [];
  String? _filter;
  String _search = '';
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.logs(silent: silent);
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isSuper = session.user?.isSuperAdmin ?? false;
    // Filtre secenekleri gelen kayitlardan turetilir; bos liste olmaz.
    final actions = _items.map((l) => l.action).toSet().toList()..sort();
    final filtered = _filter == null
        ? _items
        : _items.where((l) => l.action == _filter).toList();
    final query = normalizeSearch(_search.trim());
    final shown = query.isEmpty
        ? filtered
        : filtered
              .where(
                (log) => normalizeSearch(
                  '${log.action} ${log.details ?? ''} ${log.username ?? ''} ${log.storeName ?? ''}',
                ).contains(query),
              )
              .toList();
    final now = DateTime.now();
    final today = _items.where((log) {
      final at = DateTime.tryParse(log.createdAt)?.toLocal();
      return at != null &&
          at.year == now.year &&
          at.month == now.month &&
          at.day == now.day;
    }).length;

    return CrudScaffold(
      title: 'Hareket Kayıtları',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      emptyText: _filter == null
          ? 'Kayıt bulunamadı.'
          : 'Bu işlem türünde kayıt yok.',
      banner: actions.isEmpty
          ? null
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _AuditStat(
                        label: 'TOPLAM',
                        value: '${_items.length}',
                        note: 'Sistem Logu',
                        icon: Icons.storage_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AuditStat(
                        label: 'BUGÜN',
                        value: '$today İşlem',
                        note: session.user?.storeName ?? 'Merkez Şube',
                        icon: Icons.today_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: _AuditStat(
                        label: 'EŞİTLEME',
                        value: 'Canlı',
                        note: 'Anlık Senkron',
                        icon: Icons.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.all(10),
                  child: DropdownButtonFormField<String?>(
                    initialValue: _filter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'İŞLEM TÜRÜ'),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tüm İşlemler (${_items.length})'),
                      ),
                      ...actions.map(
                        (a) =>
                            DropdownMenuItem<String?>(value: a, child: Text(a)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                const SizedBox(height: 9),
                TextField(
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    hintText: 'Kayıt veya personel ara…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ],
            ),
      children: shown
          .map(
            (log) => AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: t.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      logIcon(log.action),
                      size: 17,
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.action,
                          style: TextStyle(
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: t.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          log.details ?? '-',
                          style: TextStyle(
                            fontSize: AppFontSize.bodyLarge,
                            color: t.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            fmtDateTime(log.createdAt),
                            log.username ?? 'sistem',
                            if (isSuper) log.storeName ?? 'genel',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _AuditStat extends StatelessWidget {
  const _AuditStat({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });

  final String label;
  final String value;
  final String note;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppFontSize.micro,
                  fontWeight: FontWeight.w800,
                  color: t.muted,
                ),
              ),
              Icon(icon, size: 14, color: t.primary),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.w800,
              color: t.ink,
            ),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppFontSize.micro, color: t.muted),
          ),
        ],
      ),
    );
  }
}
