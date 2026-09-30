import 'package:flutter/material.dart';

/// Profil sayfasinin gosterdigi kullanici karti.
///
/// Gercek User modelinden bagimsiz tutuldu: bu sayfa tasarim onizlemesi
/// olarak calisir, ileride User.fromProfile gibi bir koprudan beslenebilir.
@immutable
class ProfileUser {
  const ProfileUser({
    required this.name,
    required this.title,
    required this.bio,
    required this.initials,
    required this.followers,
    required this.following,
    required this.posts,
  });

  final String name;
  final String title;
  final String bio;
  final String initials;
  final int followers;
  final int following;
  final int posts;

  /// Tasarim onizlemesi icin ornek veri.
  static const ProfileUser sample = ProfileUser(
    name: 'Elif Yılmaz',
    title: 'Kıdemli Ürün Tasarımcısı',
    bio:
        'Tasarım sistemleri ve mobil deneyimler üzerine çalışıyorum. '
        'Kahve, tipografi ve minimal arayüzler tutkulum.',
    initials: 'EY',
    followers: 12840,
    following: 342,
    posts: 56,
  );
}

/// Ayarlar grubundaki tek satirin verisi.
@immutable
class ProfileSetting {
  const ProfileSetting({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.initialValue = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool initialValue;
}

const List<ProfileSetting> kProfileSettings = <ProfileSetting>[
  ProfileSetting(
    icon: Icons.notifications_outlined,
    title: 'Bildirimler',
    subtitle: 'Anlık bildirimleri al',
    initialValue: true,
  ),
  ProfileSetting(
    icon: Icons.lock_outline_rounded,
    title: 'Gizli Profil',
    subtitle: 'Profilin sadece takipçilerin tarafından görünsün',
  ),
  ProfileSetting(
    icon: Icons.mark_email_unread_outlined,
    title: 'E-posta Özetleri',
    subtitle: 'Haftalık aktivite özeti gönderilsin',
  ),
];
