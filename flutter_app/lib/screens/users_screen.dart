import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../core/new_theme.dart';
import '../core/user_rules.dart';
import '../models/dashboard.dart';
import '../models/store.dart';
import '../models/user.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<ManagedUser> _items = const [];
  List<StoreOption> _stores = const [];
  String _search = '';
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (session.user?.canManage ?? false) {
      repo
          .stores(silent: true)
          .then((s) {
            if (mounted) setState(() => _stores = s);
          })
          .onError((Object _, StackTrace _) {});
    }
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.userList(silent: silent);
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

  Future<void> _create() async {
    final ok = await showUserDialog(context, stores: _stores);
    if (ok == true) {
      toastSaved('Kullanıcı oluşturuldu');
      await _load(silent: true);
    }
  }

  Future<void> _edit(ManagedUser user) async {
    final ok = await showUserDialog(context, user: user, stores: _stores);
    if (ok == true) {
      toastSaved('Kullanıcı güncellendi');
      await _load(silent: true);
    }
  }

  Future<void> _resetPassword(ManagedUser user) async {
    final ok = await showPasswordResetDialog(context, user);
    if (ok == true) toastSaved('${user.fullName} şifresi güncellendi');
  }

  Future<void> _toggle(ManagedUser user) async {
    final ok = await confirmDialog(
      context,
      danger: user.active,
      title: user.active ? 'Kullanıcıyı Pasife Al' : 'Kullanıcıyı Aktifleştir',
      confirmLabel: user.active ? 'Pasife Al' : 'Aktifleştir',
      body: Text(
        user.active
            ? '${user.fullName} artık sisteme giriş yapamayacak.'
            : '${user.fullName} yeniden giriş yapabilecek.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.toggleUserActive(user);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _delete(ManagedUser user) async {
    final ok = await confirmDialog(
      context,
      title: 'Kullanıcıyı Sil',
      confirmLabel: 'Sil',
      body: Text(
        '${user.fullName} (${user.username}) kalıcı olarak silinecek. '
        'Geçmiş hareket kayıtları korunur.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteUser(user);
    } catch (_) {}
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterUsers(_items, _search);
    final activeCount = _items.where((u) => u.active).length;

    return Scaffold(
      backgroundColor: NewTokens.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loaded
                  ? _error != null
                        ? Center(child: Text(_error!))
                        : RefreshIndicator(
                            onRefresh: () => _load(silent: true),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildSubHeader(),
                                  const SizedBox(height: 16),
                                  _buildKpiCards(activeCount),
                                  const SizedBox(height: 16),
                                  _buildSearchAndFilters(),
                                  const SizedBox(height: 16),
                                  ...visible.map(
                                    (user) => _buildUserCard(user),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildQuickLinkBanner(),
                                ],
                              ),
                            ),
                          )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: FloatingActionButton(
          onPressed: () {},
          backgroundColor: NewTokens.primary,
          elevation: 4,
          shape: const CircleBorder(),
          child: const Icon(
            Icons.qr_code_scanner,
            color: NewTokens.onPrimary,
            size: 28,
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: NewTokens.surface.withValues(alpha: 0.85),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: NewTokens.tertiaryContainer,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Düzce Merkez Şube',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                Text(
                  'Ana Sayfa',
                  style: NewTokens.headlineSm.copyWith(
                    color: NewTokens.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Muhammed Ş. Sezer · Mağaza Müdürü',
                  style: NewTokens.labelSm.copyWith(
                    color: NewTokens.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications,
                      color: NewTokens.onSurfaceVariant,
                    ),
                    onPressed: () {},
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: NewTokens.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '7',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onError,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(
                  Icons.power_settings_new,
                  color: NewTokens.onSurfaceVariant,
                ),
                onPressed: () {},
              ),
              Container(
                margin: const EdgeInsets.only(left: 4),
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: NewTokens.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person,
                  color: NewTokens.onPrimary,
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Personel Listesi',
                style: NewTokens.headlineMd.copyWith(
                  color: NewTokens.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${_items.length} Personel · ${_items.where((u) => u.active).length} Aktif, ${_items.where((u) => !u.active).length} İzinli/Pasif',
                style: NewTokens.labelSm.copyWith(
                  color: NewTokens.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Yeni Kullanıcı'),
          style: ElevatedButton.styleFrom(
            backgroundColor: NewTokens.primary,
            foregroundColor: NewTokens.onPrimary,
            textStyle: NewTokens.labelLg,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCards(int activeCount) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            title: 'TOPLAM',
            value: '${_items.length} Kişi',
            iconColor: NewTokens.tertiary,
            iconWidget: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: NewTokens.tertiary,
                shape: BoxShape.circle,
              ),
            ),
            badgeText: 'Tam Kadro',
            badgeBg: NewTokens.secondaryContainer.withValues(alpha: 0.4),
            badgeColor: NewTokens.tertiary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            title: 'GÖREVDE',
            value: '$activeCount Kişi',
            iconColor: NewTokens.onSurfaceVariant,
            iconWidget: const Icon(
              Icons.schedule,
              size: 14,
              color: NewTokens.onSurfaceVariant,
            ),
            badgeText:
                '${activeCount > 0 ? activeCount - 1 : 0} Barista · 1 Şef',
            badgeBg: NewTokens.surfaceContainer,
            badgeColor: NewTokens.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            title: 'YETKİ',
            value: '0 Talep',
            iconColor: NewTokens.tertiary,
            iconWidget: const Icon(
              Icons.verified_user,
              size: 14,
              color: NewTokens.tertiary,
            ),
            badgeText: 'Güncel',
            badgeBg: NewTokens.secondaryContainer.withValues(alpha: 0.4),
            badgeColor: NewTokens.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            style: NewTokens.bodyMd.copyWith(color: NewTokens.onSurface),
            decoration: InputDecoration(
              hintText: 'Personel, kullanıcı adı veya unvan...',
              hintStyle: NewTokens.bodyMd.copyWith(color: NewTokens.outline),
              prefixIcon: const Icon(
                Icons.search,
                color: NewTokens.outline,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _FilterPill(text: 'Tümü (${_items.length})', isActive: true),
              _FilterPill(
                text:
                    'Barista (${_items.where((u) => u.role == 'barista').length})',
                isActive: false,
              ),
              _FilterPill(
                text:
                    'Supervisor (${_items.where((u) => u.role == 'shift_supervisor').length})',
                isActive: false,
              ),
              _FilterPill(
                text: 'Pasifler (${_items.where((u) => !u.active).length})',
                isActive: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserCard(ManagedUser user) {
    final perm = permissionsFor(session.user, user);

    final parts = user.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();

    final roleStr = roleLabels[user.role] ?? user.role;
    final isBarista = user.role == 'barista';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: user.active
            ? NewTokens.surfaceContainerLowest
            : NewTokens.surfaceContainerLowest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: user.active
                      ? (isBarista
                            ? NewTokens.secondaryContainer
                            : NewTokens.surfaceContainerHighest)
                      : NewTokens.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  letters,
                  style: NewTokens.headlineSm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: user.active
                        ? (isBarista
                              ? NewTokens.onSecondaryContainer
                              : NewTokens.primary)
                        : NewTokens.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName.toUpperCase(),
                      style: NewTokens.headlineSm.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: NewTokens.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${user.username}',
                      style: NewTokens.bodySm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: user.active
                      ? NewTokens.secondaryContainer.withValues(alpha: 0.5)
                      : NewTokens.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: user.active
                            ? NewTokens.tertiary
                            : NewTokens.outline,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      user.active ? 'Aktif' : 'Pasif',
                      style: NewTokens.labelSm.copyWith(
                        fontSize: 11,
                        color: user.active
                            ? NewTokens.onSecondaryFixedVariant
                            : NewTokens.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isBarista
                      ? NewTokens.surfaceContainerHighest
                      : NewTokens.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  roleStr,
                  style: NewTokens.labelSm.copyWith(
                    fontSize: 11,
                    color: isBarista ? NewTokens.primary : NewTokens.onPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  user.isMultiStore
                      ? '${user.storeIds.length} Mağaza'
                      : (user.storeName ?? 'Tüm Mağazalar').toUpperCase(),
                  style: NewTokens.labelSm.copyWith(
                    fontSize: 11,
                    color: NewTokens.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainerLow.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.verified,
                      size: 16,
                      color: user.active
                          ? NewTokens.primary
                          : NewTokens.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        user.role == 'super_admin'
                            ? 'Tüm Yetkiler'
                            : user.permissions.isEmpty
                            ? 'Yalnızca Satış (Kısıtlı)'
                            : 'Yetkiler: ${user.permissions.map((p) => permissionLabels[p] ?? p).join(', ')}',
                        style: NewTokens.bodySm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.pace,
                      size: 16,
                      color: user.active
                          ? NewTokens.tertiary
                          : NewTokens.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        user.active
                            ? 'Bu Hafta: 40 Saat · Bugün: Açılış'
                            : 'Yıllık İzin',
                        style: NewTokens.bodySm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.edit,
                  label: 'Düzenle',
                  color: NewTokens.onSurface,
                  bgColor: NewTokens.surfaceContainerLow,
                  onPressed: perm.canEdit ? () => _edit(user) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.lock_reset,
                  label: 'Şifre',
                  color: NewTokens.onSurface,
                  bgColor: NewTokens.surfaceContainerLow,
                  onPressed: perm.canResetPassword
                      ? () => _resetPassword(user)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: user.active ? Icons.pause_circle : Icons.play_circle,
                  label: user.active ? 'Pasif' : 'Aktifleştir',
                  color: user.active
                      ? NewTokens.onSurfaceVariant
                      : NewTokens.primary,
                  bgColor: user.active
                      ? NewTokens.surfaceContainerLow
                      : NewTokens.secondaryContainer.withValues(alpha: 0.6),
                  onPressed: perm.canToggleActive ? () => _toggle(user) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.delete,
                  label: 'Sil',
                  color: NewTokens.error,
                  bgColor: NewTokens.errorContainer.withValues(alpha: 0.6),
                  onPressed: perm.canDelete ? () => _delete(user) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinkBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: NewTokens.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.admin_panel_settings,
              color: NewTokens.onPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rol ve Yetki Şablonları',
                  style: NewTokens.labelLg.copyWith(
                    color: NewTokens.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Barista, Supervisor ve Şef yetkilerini düzenleyin',
                  style: NewTokens.labelSm.copyWith(
                    color: NewTokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: NewTokens.onSurfaceVariant,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: NewTokens.surface.withValues(alpha: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomNavItem(
            icon: Icons.dashboard,
            label: 'Ana Sayfa',
            isActive: true,
          ),
          _BottomNavItem(icon: Icons.inventory_2, label: 'Ürünler'),
          _BottomNavItem(icon: Icons.timer, label: 'Öneri / SKT', badge: '72'),
          _BottomNavItem(icon: Icons.monitoring, label: 'Rapor'),
          _BottomNavItem(icon: Icons.widgets, label: 'Menü'),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final Color iconColor;
  final Widget iconWidget;
  final String badgeText;
  final Color badgeBg;
  final Color badgeColor;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.iconColor,
    required this.iconWidget,
    required this.badgeText,
    required this.badgeBg,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
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
                title,
                style: NewTokens.labelSm.copyWith(
                  fontSize: 10,
                  color: NewTokens.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              iconWidget,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: NewTokens.headlineSm.copyWith(
              color: title == 'TOPLAM' || title == 'GÖREVDE'
                  ? (title == 'TOPLAM'
                        ? NewTokens.primary
                        : NewTokens.onSurface)
                  : NewTokens.tertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String text;
  final bool isActive;
  const _FilterPill({required this.text, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? NewTokens.primary : NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        style: NewTokens.labelSm.copyWith(
          color: isActive ? NewTokens.onPrimary : NewTokens.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: onPressed == null ? 0.5 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: NewTokens.labelSm.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final String? badge;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? NewTokens.primary : NewTokens.onSurfaceVariant;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: color, size: 22),
              if (badge != null)
                Positioned(
                  top: -4,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: NewTokens.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: NewTokens.labelSm.copyWith(
                        fontSize: 9,
                        color: NewTokens.onError,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: NewTokens.labelSm.copyWith(
              color: color,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showUserDialog(
  BuildContext context, {
  ManagedUser? user,
  required List<StoreOption> stores,
}) {
  final current = session.user;
  final username = TextEditingController(text: user?.username ?? '');
  final password = TextEditingController();
  final fullName = TextEditingController(text: user?.fullName ?? '');
  final roles = [...assignableRoles(current)];
  if (roles.isEmpty) roles.add('barista');
  var role = user?.role ?? roles.last;
  final selected = <String>{
    ...(user?.permissions ?? const ['discard', 'ikram']),
  };
  final grantable = grantablePermissions(current);
  int? storeId =
      user?.storeId ??
      (current?.isSuperAdmin == true ? null : current?.storeId);
  var active = user?.active ?? true;
  final selectedStores = <int>{...(user?.storeIds ?? const <int>[])};
  final isSuper = current?.isSuperAdmin ?? false;
  final lockRole = user != null && roleLocked(current, user);

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: user == null ? 'Yeni Kullanıcı' : 'Kullanıcıyı Düzenle',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) => [
        LabeledField(
          label: 'Ad Soyad',
          child: TextField(
            controller: fullName,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        if (user == null) ...[
          FormRow(
            left: LabeledField(
              label: 'Kullanıcı Adı',
              child: TextField(
                controller: username,
                autocorrect: false,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            right: LabeledField(
              label: 'Şifre',
              hint: 'En az 6 karakter.',
              child: TextField(
                controller: password,
                obscureText: true,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
        LabeledField(
          label: 'Yetki',
          hint: lockRole ? 'Kendi rolünüzü değiştiremezsiniz.' : null,
          child: DropdownButtonFormField<String>(
            initialValue: roles.contains(role) ? role : roles.first,
            isExpanded: true,
            items: roles
                .map(
                  (r) => DropdownMenuItem(
                    value: r,
                    child: Text(roleLabels[r] ?? r),
                  ),
                )
                .toList(),
            onChanged: lockRole
                ? null
                : (v) {
                    role = v ?? role;
                    if (role == 'super_admin') storeId = null;
                    rebuild();
                  },
          ),
        ),
        if (multiStoreRoles.contains(role) && stores.isNotEmpty)
          LabeledField(
            label: 'Sorumlu Olduğu Mağazalar',
            hint: 'Seçilen mağazaların verilerini görebilir.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: stores.map((store) {
                return CheckboxListTile(
                  value: selectedStores.contains(store.id),
                  onChanged: (v) {
                    if (v == true) {
                      selectedStores.add(store.id);
                    } else {
                      selectedStores.remove(store.id);
                    }
                    rebuild();
                  },
                  title: Text(store.name, style: const TextStyle(fontSize: 14)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }).toList(),
            ),
          )
        else if (isSuper &&
            !multiStoreRoles.contains(role) &&
            role != 'super_admin')
          LabeledField(
            label: 'Mağaza',
            child: DropdownButtonFormField<int?>(
              initialValue: storeId,
              isExpanded: true,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Mağaza atanmamış'),
                ),
                ...stores.map(
                  (s) =>
                      DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                ),
              ],
              onChanged: (v) {
                storeId = v;
                rebuild();
              },
            ),
          ),
        if (role != 'super_admin')
          LabeledField(
            label: 'Yetkiler',
            hint: grantable.length < allPermissions.length
                ? 'Yalnızca kendi sahip olduğunuz yetkileri verebilirsiniz.'
                : 'İşaretlenmeyen yetkiyle bu kullanıcı o işlemi yapamaz.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: allPermissions.map((permission) {
                final allowed = grantable.contains(permission);
                return CheckboxListTile(
                  value: selected.contains(permission),
                  onChanged: allowed
                      ? (v) {
                          if (v == true) {
                            selected.add(permission);
                          } else {
                            selected.remove(permission);
                          }
                          rebuild();
                        }
                      : null,
                  title: Text(
                    permissionLabels[permission] ?? permission,
                    style: const TextStyle(fontSize: 14),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }).toList(),
            ),
          ),
        if (user != null && permissionsFor(current, user).canToggleActive)
          SwitchListTile(
            value: active,
            onChanged: (v) {
              active = v;
              rebuild();
            },
            title: const Text('Aktif'),
            contentPadding: EdgeInsets.zero,
          ),
      ],
      onSubmit: () async {
        if (fullName.text.trim().isEmpty) return 'Ad soyad zorunludur';
        try {
          if (user == null) {
            if (username.text.trim().isEmpty) return 'Kullanıcı adı zorunludur';
            if (password.text.length < 6) {
              return 'Şifre en az 6 karakter olmalıdır';
            }
            await repo.createUser(
              username: username.text.trim(),
              password: password.text,
              fullName: fullName.text.trim(),
              role: role,
              storeId: multiStoreRoles.contains(role) || role == 'super_admin'
                  ? null
                  : storeId,
              active: true,
              permissions: role == 'super_admin' ? null : selected.toList(),
              storeIds: multiStoreRoles.contains(role)
                  ? selectedStores.toList()
                  : null,
            );
          } else {
            await repo.updateUser(
              id: user.id,
              fullName: fullName.text.trim(),
              role: role,
              active: permissionsFor(current, user).canToggleActive
                  ? active
                  : null,
              storeId: multiStoreRoles.contains(role) || role == 'super_admin'
                  ? null
                  : storeId,
              includeStore: isSuper,
              permissions: role == 'super_admin' ? null : selected.toList(),
              storeIds: multiStoreRoles.contains(role)
                  ? selectedStores.toList()
                  : null,
            );
          }
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

Future<bool?> showPasswordResetDialog(BuildContext context, ManagedUser user) {
  final password = TextEditingController();
  final repeat = TextEditingController();

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: '${user.fullName} — Şifre Belirle',
      submitLabel: 'Şifreyi Kaydet',
      fields: (context, rebuild) => [
        FormRow(
          left: LabeledField(
            label: 'Yeni Şifre',
            hint: 'En az 6 karakter.',
            child: TextField(
              controller: password,
              obscureText: true,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          right: LabeledField(
            label: 'Tekrar',
            child: TextField(
              controller: repeat,
              obscureText: true,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
      onSubmit: () async {
        if (password.text.length < 6) return 'Şifre en az 6 karakter olmalıdır';
        if (password.text != repeat.text) {
          return 'Şifreler birbiriyle aynı değil';
        }
        try {
          await repo.resetUserPassword(user.id, password.text);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}
