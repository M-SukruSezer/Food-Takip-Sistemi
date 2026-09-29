import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/tokens.dart';
import 'profile_page_models.dart';
import 'profile_page_widgets.dart';

/// Profil sayfasinin bagimsiz onizleme girdisi.
///
/// Uygulama icinde bu ekran su an routelara bagli DEGIL; mevcut
/// screens/profile_screen.dart (foto/parola/tema yonetimi yapan) yerinde
/// duruyor. Bu sayfa tasarim onizlemesidir: main() yerine bu sinifi
/// gecici olarak kosarak incelenebilir.
class ProfilePageApp extends StatelessWidget {
  const ProfilePageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Profil Önizleme',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const ProfilePage(),
    );
  }
}

/// Onizleme profil sayfasi: avatar, istatistikler, ayarlar ve cikis.
///
/// Callback'ler verilmezse demo davranisi (snackbar/diyalog) calisir;
/// verilirse sayfa uygulama icerisine baglanabilir hale gelir.
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.user = ProfileUser.sample,
    this.onEdit,
    this.onShare,
    this.onAvatarTap,
    this.onSignOut,
    this.onStatTap,
    this.settings = kProfileSettings,
  });

  final ProfileUser user;

  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onSignOut;
  final void Function(String label)? onStatTap;
  final List<ProfileSetting> settings;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final List<bool> _settingValues =
      List<bool>.from(widget.settings.map((s) => s.initialValue));

  ProfileUser get _effectiveUser {
    final sUser = session.user;
    if (sUser != null && widget.user == ProfileUser.sample) {
      final name = sUser.fullName.isNotEmpty ? sUser.fullName : sUser.username;
      final parts = name.trim().split(RegExp(r'\s+'));
      final initials = parts.length > 1
          ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
          : (name.isNotEmpty ? name[0].toUpperCase() : 'U');
      return ProfileUser(
        name: name,
        title: sUser.storeName ?? sUser.role,
        bio: 'Food Takip Sistemi • ${sUser.role}',
        initials: initials,
        followers: widget.user.followers,
        following: widget.user.following,
        posts: widget.user.posts,
      );
    }
    return widget.user;
  }

  void _demo(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  Future<void> _handleSignOut() async {
    if (widget.onSignOut != null) {
      widget.onSignOut!();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış yap?'),
        content: const Text('Hesabından çıkış yapmak istediğine emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.tokens.danger,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _demo('Çıkış yapıldı (önizleme)');
  }

  @override
  Widget build(BuildContext context) {
    final user = _effectiveUser;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Profil',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: context.tokens.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ayarlar',
                  onPressed: () => _demo('Ayarlar ekranı yakında'),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ProfileHeaderCard(
              user: user,
              onEdit: widget.onEdit ?? () => _demo('Profil düzenleme (önizleme)'),
              onShare: widget.onShare ?? () => _demo('Bağlantı kopyalandı'),
              onAvatarTap:
                  widget.onAvatarTap ?? () => _demo('Fotoğraf seç (önizleme)'),
            ),
            const SizedBox(height: AppTokens.gap + 8),
            ProfileStatsRow(
              user: widget.user,
              onStatTap: widget.onStatTap ??
                  (label) => _demo('$label seçildi'),
            ),
            const SizedBox(height: 28),
            const ProfileSectionTitle('Ayarlar'),
            const SizedBox(height: AppTokens.gap),
            ProfileSettingsCard(
              settings: widget.settings,
              values: _settingValues,
              onChanged: (i, v) => setState(() => _settingValues[i] = v),
            ),
            const SizedBox(height: AppTokens.gap + 8),
            ProfileSignOutCard(onTap: _handleSignOut),
          ],
        ),
      ),
    );
  }
}
