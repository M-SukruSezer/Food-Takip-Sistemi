import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../widgets/panels.dart';
import 'profile_page_models.dart';

/// 12840 -> "12,8B"; 1000 altinda sayi oldugu gibi kalir.
String formatProfileCount(int value) {
  if (value >= 1000000) return _compact(value / 1000000, 'M');
  if (value >= 1000) return _compact(value / 1000, 'B');
  return value.toString();
}

String _compact(double value, String suffix) {
  final text = value == value.roundToDouble() || value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text$suffix';
}

/// Istege bagli hafif golge: kart tema'si bordurlu oldugu icin golge cok
/// kisinin altinda kalir, yalnizca karti zeminden ayirmak icin vardir.
List<BoxShadow> _softShadows(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Profil sayfasinin kart kabugu: AppCard ile ayni dil (bordurlu, yuvarlak)
/// ama uzerine hafif golge ekler.
class ProfileCardShell extends StatelessWidget {
  const ProfileCardShell({
    super.key,
    required this.child,
    this.radius = AppTokens.radiusLg,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: _softShadows(context),
      ),
      child: child,
    );
  }
}

/// Bas harfli avatar: gradyan halka + cevrimici noktasi. Dokunulabilir.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.initials,
    this.onTap,
    this.radius = 44,
  });

  final String initials;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Profil fotoğrafını değiştir',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [t.primary, t.success]),
              ),
              child: CircleAvatar(
                radius: radius,
                backgroundColor: t.card,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: radius * 0.62,
                    fontWeight: FontWeight.w800,
                    color: t.primary,
                  ),
                ),
              ),
            ),
            Positioned(
              right: radius * 0.04,
              top: radius * 0.04,
              child: Container(
                width: radius * 0.36,
                height: radius * 0.36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.success,
                  border: Border.all(color: t.card, width: 2.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Baslik karti: avatar, ad, unvan, bio ve eylem dugmeleri.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    super.key,
    required this.user,
    this.onEdit,
    this.onShare,
    this.onAvatarTap,
  });

  final ProfileUser user;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ProfileCardShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          children: [
            ProfileAvatar(initials: user.initials, onTap: onAvatarTap),
            const SizedBox(height: 16),
            Text(
              user.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.headlineLarge,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user.title,
              style: TextStyle(
                fontSize: AppFontSize.bodyLarge,
                fontWeight: FontWeight.w600,
                color: t.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              user.bio,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.body,
                height: 1.45,
                color: t.muted,
              ),
            ),
            const SizedBox(height: 20),
            _HeaderActions(onEdit: onEdit, onShare: onShare),
          ],
        ),
      ),
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({this.onEdit, this.onShare});

  final VoidCallback? onEdit;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    // Cok dar alanda dugme yaziylari tasmasin: alta aliyoruz.
    return LayoutBuilder(
      builder: (context, constraints) {
        final edit = FilledButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Profili Düzenle'),
        );
        final share = OutlinedButton.icon(
          onPressed: onShare,
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('Paylaş'),
        );
        if (constraints.maxWidth < 260) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [edit, const SizedBox(height: 10), share],
          );
        }
        return Row(
          children: [
            Expanded(child: edit),
            const SizedBox(width: 10),
            Expanded(child: share),
          ],
        );
      },
    );
  }
}

/// Uc istatistik karti; degerler StatCard ile ayni dilde gosterilir.
class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({super.key, required this.user, this.onStatTap});

  final ProfileUser user;
  final void Function(String label)? onStatTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Takipçi',
            value: formatProfileCount(user.followers),
            valueColor: t.primary,
            onTap: onStatTap == null ? null : () => onStatTap!('Takipçi'),
          ),
        ),
        const SizedBox(width: AppTokens.gap),
        Expanded(
          child: StatCard(
            label: 'Takip',
            value: formatProfileCount(user.following),
            valueColor: t.primary,
            onTap: onStatTap == null ? null : () => onStatTap!('Takip'),
          ),
        ),
        const SizedBox(width: AppTokens.gap),
        Expanded(
          child: StatCard(
            label: 'Gönderi',
            value: user.posts.toString(),
            valueColor: t.primary,
            onTap: onStatTap == null ? null : () => onStatTap!('Gönderi'),
          ),
        ),
      ],
    );
  }
}

class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFontSize.bodyLarge,
          fontWeight: FontWeight.w700,
          color: t.ink,
        ),
      ),
    );
  }
}

/// Ayarlar grubu; satir durumu SAYFADA tutulur (tile state'siz), boylece
/// grup yeniden kuruldugunda secimler kaybolmaz.
class ProfileSettingsCard extends StatelessWidget {
  const ProfileSettingsCard({
    super.key,
    required this.settings,
    required this.values,
    required this.onChanged,
  });

  final List<ProfileSetting> settings;
  final List<bool> values;
  final void Function(int index, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ProfileCardShell(
      child: Column(
        children: [
          for (var i = 0; i < settings.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 70, endIndent: 16, color: t.border),
            _ProfileSettingTile(
              setting: settings[i],
              value: values[i],
              onChanged: (v) => onChanged(i, v),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileSettingTile extends StatelessWidget {
  const _ProfileSettingTile({
    required this.setting,
    required this.value,
    required this.onChanged,
  });

  final ProfileSetting setting;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: t.primarySoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Icon(setting.icon, size: 20, color: t.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    setting.title,
                    style: TextStyle(
                      fontSize: AppFontSize.bodyLarge,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    setting.subtitle,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: t.muted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Cikis karti: tehlikeli eylem oldugu icin dangerSoft/danger cifti kullanir.
class ProfileSignOutCard extends StatelessWidget {
  const ProfileSignOutCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ProfileCardShell(
      radius: AppTokens.radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.dangerSoft,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: Icon(Icons.logout_rounded, size: 20, color: t.danger),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Çıkış Yap',
                        style: TextStyle(
                          fontSize: AppFontSize.bodyLarge,
                          fontWeight: FontWeight.w600,
                          color: t.danger,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hesabından güvenli bir şekilde çık',
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
