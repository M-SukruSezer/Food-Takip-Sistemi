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
import '../widgets/login_branding_editor.dart';

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

  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;

  bool _notifySkt = true;
  bool _notifyShift = true;
  bool _notifyReport = true;

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

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // 1. Üst Başlık & Durum
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profil & Sistem Ayarları',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Kişisel hesap tercihleri ve uygulama ayarları',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: t.successSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.success,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Senkronize',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.okText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. Kullanıcı Profil Kartı
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: t.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: t.border, width: 1.5),
                          ),
                          child: user.avatar != null
                              ? Avatar(user: user, size: 68)
                              : Container(
                                  color: const Color(0xFFE2E8F0),
                                  child: Icon(
                                    Icons.person,
                                    size: 40,
                                    color: t.muted,
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: t.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: t.ink,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          roleLabels[user.role] ?? user.role,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${user.username}${user.storeName != null ? ' · ${user.storeName}' : ''}',
                          style: TextStyle(fontSize: 11, color: t.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: t.successSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: t.success.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: t.success,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Aktif · ${user.canManage ? 'Yönetici' : 'Personel'}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: t.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 2 Bilgi Kutusu: Sicil No & Kayıt Tarihi
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: t.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.badge_outlined,
                            size: 20,
                            color: t.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sicil No',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: t.muted,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '#${user.id.toString().padLeft(4, '0')}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: t.ink,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFDBEAFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kayıt Tarihi',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: t.muted,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '14.06.2025',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: t.ink,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        if (user.isSuperAdmin) ...[
          const LoginBrandingEditor(),
          const SizedBox(height: AppTokens.gap),
        ],
        // 3. Profil Fotoğrafı Kartı
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderTitleWithIcon(
                icon: Icons.photo_camera_outlined,
                title: 'Profil Fotoğrafı',
                subtitle: 'Görsel boyutlandırma ve portre ayarı',
              ),
              if (_avatarError != null) ...[
                const SizedBox(height: 10),
                AppAlert(message: _avatarError!),
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: t.primarySoft,
                    foregroundColor: t.primary,
                    side: BorderSide(color: t.primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _savingAvatar ? null : _pickAvatar,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(
                    user.avatar == null
                        ? 'Fotoğraf Yükle'
                        : 'Fotoğrafı Değiştir',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (user.avatar != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEF2F2),
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _savingAvatar ? null : _removeAvatar,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text(
                      'Kaldır',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Seçtiğiniz fotoğraf otomatik olarak kare şekilde kırpılıp 256×256 boyutuna küçültülür.',
                style: TextStyle(fontSize: 11, color: t.muted, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        // 4. Görünüm & Tema Kartı
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderTitleWithIcon(
                icon: Icons.palette_outlined,
                title: 'Görünüm & Tema',
                subtitle: 'Ekran renk modunu özelleştirin.\nSeçiminiz bu cihazda saklanır ve giriş ekranı dahil tüm ekranlarda geçerli olur.',
              ),
              const SizedBox(height: 14),
              AnimatedBuilder(
                animation: themePreference,
                builder: (context, _) {
                  final dark = themePreference.isDark;
                  return Column(
                    children: [
                      _ThemeChoiceTile(
                        selected: !dark,
                        icon: Icons.light_mode_outlined,
                        title: 'Açık Tema',
                        onTap: () => themePreference.set(false),
                      ),
                      const SizedBox(height: 8),
                      _ThemeChoiceTile(
                        selected: dark,
                        icon: Icons.dark_mode_outlined,
                        title: 'Koyu Tema',
                        onTap: () => themePreference.set(true),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        // 5. Şifre ve Güvenlik Kartı
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderTitleWithIcon(
                icon: Icons.security_outlined,
                title: 'Şifre ve Güvenlik',
                subtitle: 'Hesap erişim bilgilerinizi tazeleyin',
              ),
              if (_passwordError != null) ...[
                const SizedBox(height: 10),
                AppAlert(message: _passwordError!),
              ],
              const SizedBox(height: 14),
              _CustomPasswordField(
                label: 'Mevcut Şifre',
                controller: _current,
                obscureText: _obscureCurrent,
                hintText: '••••••••',
                onToggleVisibility: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              const SizedBox(height: 10),
              _CustomPasswordField(
                label: 'Yeni Şifre',
                controller: _next,
                obscureText: _obscureNext,
                hintText: 'En az 8 karakter',
                onToggleVisibility: () =>
                    setState(() => _obscureNext = !_obscureNext),
              ),
              const SizedBox(height: 10),
              _CustomPasswordField(
                label: 'Yeni Şifre (Tekrar)',
                controller: _confirm,
                obscureText: _obscureConfirm,
                hintText: 'Yeni şifrenizi tekrar girin',
                onToggleVisibility: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Color(0xFF2563EB),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Şifreniz en az 8 karakter; bir büyük harf ve bir rakam içermelidir.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1E40AF),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: t.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _savingPassword ? null : _changePassword,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    _savingPassword ? 'Kaydediliyor...' : 'Şifreyi Güncelle',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        // 6. Bildirim Tercihleri Kartı
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderTitleWithIcon(
                icon: Icons.notifications_outlined,
                title: 'Bildirim Tercihleri',
                subtitle: 'Mobil uyarı ve ses yapılandırması',
              ),
              const SizedBox(height: 14),
              _NotificationPrefRow(
                title: 'Kritik SKT Bildirimleri',
                subtitle: '24 saatten az kalan ürünler için push uyarıları',
                value: _notifySkt,
                onChanged: (v) => setState(() => _notifySkt = v),
              ),
              _NotificationPrefRow(
                title: 'Vardiya & İzin Hatırlatıcıları',
                subtitle: 'Vardiya başlamadan 30 dk önce haber ver',
                value: _notifyShift,
                onChanged: (v) => setState(() => _notifyShift = v),
              ),
              _NotificationPrefRow(
                title: 'Günlük Kasa / Ciro Raporu',
                subtitle: 'Gün kapanışında anlık özet gönderimi',
                value: _notifyReport,
                onChanged: (v) => setState(() => _notifyReport = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),

        // 7. Oturum Kartı
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Oturum',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'v2.4.1 (Build 1084)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: t.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Mevcut cihazdaki mağaza müdürlük yetkiniz kapatılır ve pin ekranına yönlendirilirsiniz.',
                style: TextStyle(fontSize: 11, color: t.muted, height: 1.3),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => confirmSignOut(context),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text(
                    'Çıkış Yap',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderTitleWithIcon extends StatelessWidget {
  const _HeaderTitleWithIcon({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: t.primarySoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border),
          ),
          child: Icon(icon, size: 20, color: t.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: t.muted, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeChoiceTile extends StatelessWidget {
  const _ThemeChoiceTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? t.primary : t.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? t.primary : t.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? t.onPrimary : t.muted),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : t.ink,
                ),
              ),
              const Spacer(),
              if (selected)
                const Icon(Icons.check_circle, color: Colors.white, size: 20)
              else
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomPasswordField extends StatelessWidget {
  const _CustomPasswordField({
    required this.label,
    required this.controller,
    required this.obscureText,
    required this.onToggleVisibility,
    this.hintText,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final VoidCallback onToggleVisibility;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscureText,
                  style: TextStyle(fontSize: 14, color: t.ink),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(fontSize: 13, color: t.muted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggleVisibility,
                icon: Icon(
                  obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: t.muted,
                ),
                splashRadius: 20,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotificationPrefRow extends StatelessWidget {
  const _NotificationPrefRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: t.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: value,
              activeThumbColor: t.primary,
              activeTrackColor: t.primarySoft,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
