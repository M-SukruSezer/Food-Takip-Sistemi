import re

with open('lib/screens/profile_screen.dart', 'r') as f:
    content = f.read()

# We need to replace everything from `  @override\n  Widget build(BuildContext context) {` to the end.
match = re.search(r'  @override\n  Widget build\(BuildContext context\) \{', content)
if not match:
    print("Could not find build method")
    exit(1)

prefix = content[:match.start()]

new_build = """  @override
  Widget build(BuildContext context) {
    final user = session.user;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: NewTokens.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profil & Sistem Ayarları',
                          style: NewTokens.headlineMd.copyWith(
                            color: NewTokens.onSurface,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Kişisel hesap tercihleri ve uygulama ayarları',
                          style: NewTokens.bodySm.copyWith(
                            color: NewTokens.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: NewTokens.secondaryContainer.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: NewTokens.tertiaryContainer,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Senkronize',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: NewTokens.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  
                  // User Profile Card
                  _buildProfileCard(user),
                  const SizedBox(height: 16),
                  
                  // Profil Fotoğrafı
                  _buildPhotoManagement(user),
                  const SizedBox(height: 16),
                  
                  // Görünüm & Tema
                  _buildThemeManagement(),
                  const SizedBox(height: 16),
                  
                  // Şifre Değiştir
                  _buildPasswordManagement(),
                  const SizedBox(height: 16),
                  
                  // Bildirim Tercihleri
                  _buildNotificationPreferences(),
                  const SizedBox(height: 16),
                  
                  // Oturum ve Uygulama Bilgisi
                  _buildSessionManagement(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(User user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar part
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: user.avatar != null
                        ? Image.network(user.avatar!, fit: BoxFit.cover)
                        : Icon(Icons.person, size: 32, color: NewTokens.onSurfaceVariant),
                  ),
                  Positioned(
                    bottom: -4,
                    right: -4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: NewTokens.tertiaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: NewTokens.surfaceContainerLowest,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              
              // Info part
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName.toUpperCase(),
                      style: NewTokens.headlineSm.copyWith(
                        color: NewTokens.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roleLabels[user.role] ?? user.role,
                      style: NewTokens.labelMd.copyWith(
                        color: NewTokens.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '@${user.username} · ${user.storeName?.toUpperCase() ?? 'MERKEZİ'}',
                      style: NewTokens.bodySm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: NewTokens.secondaryContainer,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: NewTokens.tertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Aktif Yönetici',
                            style: NewTokens.labelSm.copyWith(
                              color: NewTokens.onSecondaryContainer,
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
          
          const SizedBox(height: 16),
          
          // Quick Info Strip
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: NewTokens.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.badge, size: 18, color: NewTokens.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sicil No', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                            Text('#48291', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: NewTokens.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, size: 18, color: NewTokens.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kayıt Tarihi', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                            Text('14.06.2024', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    );
  }

  Widget _buildPhotoManagement(User user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.add_a_photo, size: 20, color: NewTokens.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Profil Fotoğrafı', style: NewTokens.headlineSm.copyWith(fontSize: 16, color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                    Text('Görsel boyutlandırma ve portre ayarı', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if (_avatarError != null) ...[
            const SizedBox(height: 8),
            Text(_avatarError!, style: NewTokens.bodySm.copyWith(color: NewTokens.error)),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: _savingAvatar ? null : _pickAvatar,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_camera, size: 20, color: NewTokens.primary),
                  const SizedBox(width: 8),
                  Text(
                    user.avatar == null ? 'Fotoğraf Yükle' : 'Fotoğrafı Değiştir',
                    style: NewTokens.labelLg.copyWith(color: NewTokens.primary),
                  ),
                ],
              ),
            ),
          ),
          if (user.avatar != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: _savingAvatar ? null : _removeAvatar,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: NewTokens.errorContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.delete, size: 19, color: NewTokens.error),
                    const SizedBox(width: 8),
                    Text('Kaldır', style: NewTokens.labelLg.copyWith(color: NewTokens.error)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Seçtiğiniz fotoğraf otomatik olarak kare şekilde kırpılıp 256×256 boyutuna küçültülür.',
            style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeManagement() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.palette, size: 20, color: NewTokens.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Görünüm & Tema', style: NewTokens.headlineSm.copyWith(fontSize: 16, color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                    Text('Ekran renk modunu özelleştirin', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Seçiminiz bu cihazda saklanır ve giriş ekranı dahil tüm ekranlarda geçerli olur.',
            style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: themePreference,
            builder: (context, _) {
              final dark = themePreference.isDark;
              return Column(
                children: [
                  _ThemeOption(
                    icon: Icons.wb_sunny,
                    label: 'Açık Tema',
                    selected: !dark,
                    onTap: () => themePreference.set(false),
                  ),
                  const SizedBox(height: 8),
                  _ThemeOption(
                    icon: Icons.dark_mode,
                    label: 'Koyu Tema',
                    selected: dark,
                    onTap: () => themePreference.set(true),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordManagement() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.lock_reset, size: 20, color: NewTokens.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Şifre ve Güvenlik', style: NewTokens.headlineSm.copyWith(fontSize: 16, color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                    Text('Hesap erişim bilgilerinizi tazeleyin', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if (_passwordError != null) ...[
            const SizedBox(height: 12),
            Text(_passwordError!, style: NewTokens.bodySm.copyWith(color: NewTokens.error)),
          ],
          const SizedBox(height: 16),
          _buildTextField(label: 'Mevcut Şifre', controller: _current, placeholder: '••••••••'),
          const SizedBox(height: 12),
          _buildTextField(label: 'Yeni Şifre', controller: _next, placeholder: 'En az 8 karakter'),
          const SizedBox(height: 12),
          _buildTextField(label: 'Yeni Şifre (Tekrar)', controller: _confirm, placeholder: 'Yeni şifrenizi tekrar girin'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.info, size: 18, color: NewTokens.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Şifreniz en az 8 karakter, bir büyük harf ve bir rakam içermelidir.',
                    style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _savingPassword ? null : _changePassword,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: NewTokens.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 20, color: NewTokens.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    _savingPassword ? 'Kaydediliyor...' : 'Şifreyi Güncelle',
                    style: NewTokens.labelLg.copyWith(color: NewTokens.onPrimary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({required String label, required TextEditingController controller, required String placeholder}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            obscureText: true,
            style: NewTokens.bodyMd.copyWith(color: NewTokens.onSurface),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: NewTokens.bodyMd.copyWith(color: NewTokens.outline),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: InputBorder.none,
              suffixIcon: Icon(Icons.visibility, size: 20, color: NewTokens.outline),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationPreferences() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.notifications_active, size: 20, color: NewTokens.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bildirim Tercihleri', style: NewTokens.headlineSm.copyWith(fontSize: 16, color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                    Text('Mobil uyarı ve ses yapılandırması', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSwitchItem(
            title: 'Kritik SKT Bildirimleri',
            subtitle: '24 saatten az kalan ürünler için push uyarısı',
            value: true,
            onChanged: (val) {},
          ),
          const SizedBox(height: 12),
          _buildSwitchItem(
            title: 'Vardiya & İzin Hatırlatıcıları',
            subtitle: 'Vardiya başlamadan 30 dk önce haber ver',
            value: true,
            onChanged: (val) {},
          ),
          const SizedBox(height: 12),
          _buildSwitchItem(
            title: 'Günlük Kasa / Ciro Raporu',
            subtitle: 'Gün kapanışında anlık özet gönder',
            value: true,
            onChanged: (val) {},
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchItem({required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: NewTokens.primary,
            inactiveTrackColor: NewTokens.surfaceContainer,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionManagement(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Oturum', style: NewTokens.headlineSm.copyWith(fontSize: 16, color: NewTokens.onSurface, fontWeight: FontWeight.bold)),
              Text('v2.4.1 (Build 1084)', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Mevcut cihazdaki mağaza müdürlük yetkiniz kapatılır ve pin ekranına yönlendirilirsiniz.',
            style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => confirmSignOut(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: NewTokens.error,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout, size: 20, color: NewTokens.onError),
                  const SizedBox(width: 8),
                  Text(
                    'Çıkış Yap',
                    style: NewTokens.labelLg.copyWith(color: NewTokens.onError, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Colombia Coffee Co. © 2024 · All Rights Reserved',
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: NewTokens.outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: NewTokens.primary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: NewTokens.onPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: NewTokens.labelLg.copyWith(color: NewTokens.onPrimary, fontWeight: FontWeight.bold),
                ),
              ),
              Icon(Icons.check_circle, size: 20, color: NewTokens.onPrimary),
            ],
          ),
        ),
      );
    } else {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: NewTokens.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: NewTokens.labelLg.copyWith(color: NewTokens.onSurfaceVariant),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: NewTokens.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      );
    }
}
"""

with open('lib/screens/profile_screen.dart', 'w') as f:
    f.write(prefix.replace("import '../widgets/panels.dart';", "import '../core/new_theme.dart';\nimport '../widgets/panels.dart';") + new_build)

print("Done writing")
