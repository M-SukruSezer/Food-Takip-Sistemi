import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../core/user_rules.dart';
import '../models/dashboard.dart';
import '../models/store.dart';
import '../models/user.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';

/// Kullanici yonetimi. Ana Yonetici tum magazalari, magaza yoneticisi yalnizca
/// kendi magazasini gorur (sunucu da ayni filtreyi uygular).
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
    // Magaza listesi hem filtre hem de cok magazali rol atamasi icin gerekli;
    // sunucu zaten yalnizca erisilen magazalari donuyor.
    if (session.user?.canManage ?? false) {
      repo.stores(silent: true).then((s) {
        if (mounted) setState(() => _stores = s);
      }).onError((Object _, StackTrace _) {});
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
      body: Text(user.active
          ? '${user.fullName} artık sisteme giriş yapamayacak.'
          : '${user.fullName} yeniden giriş yapabilecek.'),
    );
    if (ok != true) return;
    try {
      await repo.toggleUserActive(user);
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    await _load(silent: true);
  }

  Future<void> _delete(ManagedUser user) async {
    final ok = await confirmDialog(
      context,
      title: 'Kullanıcıyı Sil',
      confirmLabel: 'Sil',
      body: Text('${user.fullName} (${user.username}) kalıcı olarak silinecek. '
          'Geçmiş hareket kayıtları korunur.'),
    );
    if (ok != true) return;
    try {
      await repo.deleteUser(user);
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final visible = filterUsers(_items, _search);

    return CrudScaffold(
      title: 'Kullanıcılar',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      addLabel: 'Yeni Kullanıcı',
      onAdd: _create,
      emptyText: _search.isEmpty ? 'Kullanıcı bulunamadı.' : 'Aramanıza uyan kullanıcı yok.',
      banner: _items.length > 6 || _search.isNotEmpty
          ? AppCard(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(fontSize: 16),
                // Oneri listesindeki arama kutusuyla ayni gorunum: gomulu
                // zemin ve marka renginde ikon.
                decoration: InputDecoration(
                  hintText: 'Ada, kullanıcı adına veya mağazaya göre ara',
                  fillColor: t.bg,
                  prefixIcon: Icon(Icons.search, color: t.primary),
                ),
              ),
            )
          : null,
      children: visible.map((user) {
        final perm = permissionsFor(session.user, user);
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Initials(name: user.fullName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink)),
                        Text('@${user.username}',
                            style: TextStyle(fontSize: 13, color: t.muted)),
                      ],
                    ),
                  ),
                  Pill(
                    text: user.active ? 'aktif' : 'pasif',
                    color: user.active ? t.success : t.danger,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill(text: roleLabels[user.role] ?? user.role, color: t.info),
                  Pill(
                    text: user.isMultiStore
                        ? '${user.storeIds.length} mağaza sorumlusu'
                        : (user.storeName ??
                            (user.role == 'super_admin' ? 'Tüm mağazalar' : 'Mağaza atanmamış')),
                    color: t.warning,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Ana Yoneticide yetkiler rolden gelir, listelemek gurultu olur.
              if (user.role != 'super_admin')
                Text(
                  user.permissions.isEmpty
                      ? 'Ek yetki verilmemiş'
                      : 'Yetkiler: ${user.permissions.map((p) => permissionLabels[p] ?? p).join(', ')}',
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
              if (perm.reason != null) ...[
                const SizedBox(height: 4),
                Text(perm.reason!, style: TextStyle(fontSize: 12, color: t.muted)),
              ],
              const SizedBox(height: 10),
              // Islemler telefonda iki satira sarilir; her dugme tam dokunma boyunda.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: perm.canEdit ? () => _edit(user) : null,
                    child: const Text('Düzenle'),
                  ),
                  OutlinedButton(
                    onPressed: perm.canResetPassword ? () => _resetPassword(user) : null,
                    child: const Text('Şifre'),
                  ),
                  OutlinedButton(
                    onPressed: perm.canToggleActive ? () => _toggle(user) : null,
                    child: Text(user.active ? 'Pasife Al' : 'Aktifleştir'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: perm.canDelete ? t.danger : t.muted,
                      side: BorderSide(color: perm.canDelete ? t.danger : t.border),
                    ),
                    onPressed: perm.canDelete ? () => _delete(user) : null,
                    child: const Text('Sil'),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Kullanici ekle/duzenle. Sifre yalnizca yeni kullanicida sorulur; mevcut
/// kullanicinin sifresi ayri pencereden sifirlanir.
Future<bool?> showUserDialog(
  BuildContext context, {
  ManagedUser? user,
  required List<StoreOption> stores,
}) {
  final current = session.user;
  final username = TextEditingController(text: user?.username ?? '');
  final password = TextEditingController();
  final fullName = TextEditingController(text: user?.fullName ?? '');
  // Roller once cozulur; varsayilan en alt kademe (Barista).
  final roles = [...assignableRoles(current)];
  if (roles.isEmpty) roles.add('barista');
  var role = user?.role ?? roles.last;
  // Yeni kullanici zayi ve ikram ile gelir: yetki sistemi oncesi davranis
  // buydu, sunucudaki varsayilanla ayni.
  final selected = <String>{
    ...(user?.permissions ?? const ['discard', 'ikram']),
  };
  final grantable = grantablePermissions(current);
  int? storeId = user?.storeId ?? (current?.isSuperAdmin == true ? null : current?.storeId);
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
          child: TextField(controller: fullName, style: const TextStyle(fontSize: 16)),
        ),
        if (user == null) ...[
          LabeledField(
            label: 'Kullanıcı Adı',
            child: TextField(
              controller: username,
              autocorrect: false,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          LabeledField(
            label: 'Şifre',
            hint: 'En az 6 karakter olmalıdır.',
            child: TextField(
              controller: password,
              obscureText: true,
              style: const TextStyle(fontSize: 16),
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
                .map((r) => DropdownMenuItem(value: r, child: Text(roleLabels[r] ?? r)))
                .toList(),
            onChanged: lockRole
                ? null
                : (v) {
                    role = v ?? role;
                    // Ana yonetici tum magazalari gorur, magaza secimi anlamsizdir.
                    if (role == 'super_admin') storeId = null;
                    rebuild();
                  },
          ),
        ),
        // Cok magazali rol: sorumlu olunan magazalar isaretlenir.
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
        else if (isSuper && !multiStoreRoles.contains(role) && role != 'super_admin')
          LabeledField(
            label: 'Mağaza',
            child: DropdownButtonFormField<int?>(
              initialValue: storeId,
              isExpanded: true,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Mağaza atanmamış')),
                ...stores.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))),
              ],
              onChanged: (v) {
                storeId = v;
                rebuild();
              },
            ),
          ),
        // Ana Yonetici her yetkiye sahiptir, kutular anlamsiz olur.
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
                  // Veremeyecegi yetki kilitli gelir; sunucu da reddediyor.
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
                  title: Text(permissionLabels[permission] ?? permission,
                      style: const TextStyle(fontSize: 14)),
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
            if (password.text.length < 6) return 'Şifre en az 6 karakter olmalıdır';
            await repo.createUser(
              username: username.text.trim(),
              password: password.text,
              fullName: fullName.text.trim(),
              role: role,
              storeId: multiStoreRoles.contains(role) || role == 'super_admin' ? null : storeId,
              active: true,
              permissions: role == 'super_admin' ? null : selected.toList(),
              storeIds: multiStoreRoles.contains(role) ? selectedStores.toList() : null,
            );
          } else {
            await repo.updateUser(
              id: user.id,
              fullName: fullName.text.trim(),
              role: role,
              active: permissionsFor(current, user).canToggleActive ? active : null,
              storeId: multiStoreRoles.contains(role) || role == 'super_admin' ? null : storeId,
              includeStore: isSuper,
              permissions: role == 'super_admin' ? null : selected.toList(),
              storeIds: multiStoreRoles.contains(role) ? selectedStores.toList() : null,
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

/// Sifre sifirlama. Kendi sifresini de buradan degistirebilir.
Future<bool?> showPasswordResetDialog(BuildContext context, ManagedUser user) {
  final password = TextEditingController();
  final repeat = TextEditingController();

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: '${user.fullName} — Şifre Belirle',
      submitLabel: 'Şifreyi Kaydet',
      fields: (context, rebuild) => [
        LabeledField(
          label: 'Yeni Şifre',
          hint: 'En az 6 karakter olmalıdır.',
          child: TextField(
            controller: password,
            obscureText: true,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        LabeledField(
          label: 'Yeni Şifre (tekrar)',
          child: TextField(
            controller: repeat,
            obscureText: true,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
      onSubmit: () async {
        if (password.text.length < 6) return 'Şifre en az 6 karakter olmalıdır';
        if (password.text != repeat.text) return 'Şifreler birbiriyle aynı değil';
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

/// Kullanici kartinda ad bas harfleri. Yonetilen kullanicilarin fotografi
/// listede donmuyor, bu yuzden Avatar yerine harf dairesi kullanilir.
class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
      child: Text(
        letters.isEmpty ? '?' : letters,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.primaryDark),
      ),
    );
  }
}
