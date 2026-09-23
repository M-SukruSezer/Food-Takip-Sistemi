import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/avatar_image.dart';
import '../core/busy.dart';
import '../core/format.dart';
import '../core/logout.dart';
import '../core/image_pick.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/theme_mode.dart';
import '../core/tokens.dart';
import '../widgets/avatar.dart';
import '../widgets/panels.dart';

/// Profil: fotograf, kullanici bilgisi, tema secimi ve sifre degistirme.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  String? _passwordError;
  String? _avatarError;
  bool _savingPassword = false;
  bool _savingAvatar = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() => _avatarError = null);
    Uint8List? bytes;
    try {
      bytes = await pickImageBytes();
    } catch (e) {
      setState(() => _avatarError = 'Dosya seçici açılamadı: $e');
      return;
    }
    if (bytes == null) return;

    setState(() => _savingAvatar = true);
    // Kucultme ve yukleme birlikte tek yukleme katmani gosterir.
    busy.begin();
    try {
      final dataUrl = encodeAvatar(bytes);
      final saved = await repo.saveAvatar(dataUrl);
      _applyAvatar(saved);
    } on FormatException catch (e) {
      setState(() => _avatarError = e.message);
    } catch (e) {
      setState(() => _avatarError = errorMessage(e));
    } finally {
      busy.end();
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() {
      _avatarError = null;
      _savingAvatar = true;
    });
    try {
      await repo.saveAvatar(null);
      _applyAvatar(null);
    } catch (e) {
      setState(() => _avatarError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  void _applyAvatar(String? avatar) {
    final u = session.user;
    if (u == null) return;
    // copyWith kullanilir: elle kurmak yetki listesi gibi yeni alanlari
    // sessizce dusuruyordu.
    session.updateUser(u.copyWith(avatar: avatar, clearAvatar: avatar == null));
  }

  Future<void> _changePassword() async {
    setState(() => _passwordError = null);
    if (_current.text.isEmpty) {
      setState(() => _passwordError = 'Mevcut şifrenizi girin');
      return;
    }
    if (_next.text.length < 6) {
      setState(() => _passwordError = 'Yeni şifre en az 6 karakter olmalıdır');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _passwordError = 'Yeni şifreler eşleşmiyor');
      return;
    }

    setState(() => _savingPassword = true);
    try {
      await repo.changeOwnPassword(_current.text, _next.text);
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      toastSaved('Şifreniz güncellendi');
    } catch (e) {
      if (mounted) setState(() => _passwordError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = session.user;
    if (user == null) return const SizedBox.shrink();
    final narrow = MediaQuery.sizeOf(context).width < 641;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Avatar(user: user, size: narrow ? 56 : 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink)),
                    const SizedBox(height: 2),
                    Text(roleLabels[user.role] ?? user.role,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.primary)),
                    Text('@${user.username} · ${user.storeName ?? 'Merkezi'}',
                        style: TextStyle(fontSize: 13, color: t.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle('Profil Fotoğrafı'),
              if (_avatarError != null) ...[
                AppAlert(message: _avatarError!),
                const SizedBox(height: 10),
              ],
              // Telefonda dugmeler alt alta, tablet ve ustunde yan yana.
              Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                children: [
                  _FlexChild(
                    narrow: narrow,
                    child: OutlinedButton.icon(
                      onPressed: _savingAvatar ? null : _pickAvatar,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(user.avatar == null ? 'Fotoğraf Yükle' : 'Fotoğrafı Değiştir'),
                    ),
                  ),
                  if (user.avatar != null) ...[
                    SizedBox(width: narrow ? 0 : 8, height: narrow ? 8 : 0),
                    _FlexChild(
                      narrow: narrow,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.danger,
                          side: BorderSide(color: t.danger),
                        ),
                        onPressed: _savingAvatar ? null : _removeAvatar,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Kaldır'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Seçtiğiniz fotoğraf otomatik olarak kare şekilde kırpılıp 256×256 boyutuna '
                'küçültülür.',
                style: TextStyle(fontSize: 12, color: t.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle('Görünüm'),
              Text(
                'Seçiminiz bu cihazda saklanır ve giriş ekranı dahil tüm ekranlarda geçerli olur.',
                style: TextStyle(fontSize: 12, color: t.muted),
              ),
              const SizedBox(height: 10),
              AnimatedBuilder(
                animation: themePreference,
                builder: (context, _) {
                  final dark = themePreference.isDark;
                  return Flex(
                    direction: narrow ? Axis.vertical : Axis.horizontal,
                    children: [
                      _FlexChild(
                        narrow: narrow,
                        child: _ThemeButton(
                          selected: !dark,
                          icon: Icons.light_mode_outlined,
                          label: 'Açık Tema',
                          onPressed: () => themePreference.set(false),
                        ),
                      ),
                      SizedBox(width: narrow ? 0 : 8, height: narrow ? 8 : 0),
                      _FlexChild(
                        narrow: narrow,
                        child: _ThemeButton(
                          selected: dark,
                          icon: Icons.dark_mode_outlined,
                          label: 'Koyu Tema',
                          onPressed: () => themePreference.set(true),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle('Şifre Değiştir'),
              if (_passwordError != null) ...[
                AppAlert(message: _passwordError!),
                const SizedBox(height: 10),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PasswordField(label: 'Mevcut Şifre', controller: _current),
                    const SizedBox(height: 10),
                    _PasswordField(label: 'Yeni Şifre', controller: _next),
                    const SizedBox(height: 10),
                    _PasswordField(label: 'Yeni Şifre (Tekrar)', controller: _confirm),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _savingPassword ? null : _changePassword,
                      child: Text(_savingPassword ? 'Kaydediliyor...' : 'Şifreyi Güncelle'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle('Oturum'),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: t.danger),
                onPressed: () => confirmSignOut(context),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Çıkış Yap'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dar ekranda dugmeler tam genislik alir, genis ekranda esit paylasir.
class _FlexChild extends StatelessWidget {
  const _FlexChild({required this.narrow, required this.child});

  final bool narrow;
  final Widget child;

  @override
  Widget build(BuildContext context) => narrow ? child : Expanded(child: child);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
    );
    return selected
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(labelText: label),
    );
  }
}
