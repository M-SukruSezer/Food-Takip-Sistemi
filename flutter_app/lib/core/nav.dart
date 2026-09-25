import 'package:flutter/material.dart';

import '../models/user.dart';

class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.roles,
    this.inBottomBar = false,
  });

  final String path;
  final String label;
  final String shortLabel;
  final IconData icon;
  final List<String> roles;
  final bool inBottomBar;
}

/// Yan menudeki mantiksal bolum. Baslik null ise ayirici cizgiyle durur.
class NavGroup {
  const NavGroup({this.title, required this.items});

  final String? title;
  final List<NavItem> items;
}

const allRoles = [
  'super_admin',
  'operations_manager',
  'regional_manager',
  'store_manager',
  'shift_supervisor',
  'barista',
];

/// Kullanici yonetimi, cesit yonetimi ve onaylara erisen roller.
const managerRoles = ['super_admin', 'operations_manager', 'regional_manager', 'store_manager'];

/// Rapor Panelini gorebilen roller. Ust kademeler bu paneli hic gormez.
const reportPanelRoles = ['store_manager', 'shift_supervisor'];

/// Petty Cash modulunu gorebilen roller. Giris yetkisi yalnizca son ikisinde;
/// ust kademeler izleme amacli gorur.
const pettyCashRoles = [
  'super_admin',
  'operations_manager',
  'regional_manager',
  'store_manager',
  'shift_supervisor',
];

/// Yan menu mantiksal gruplara ayrildi: gunluk operasyon, para ve raporlar,
/// kurulum. React tarafindaki NAV_GROUPS ile ayni sira.
const navGroups = <NavGroup>[
  NavGroup(title: 'Operasyon', items: [
    NavItem(path: '/dashboard', label: 'Ana Sayfa', shortLabel: 'Ana Sayfa', icon: Icons.home_outlined, roles: allRoles, inBottomBar: true),
    NavItem(path: '/batches', label: 'Ürünler', shortLabel: 'Ürünler', icon: Icons.inventory_2_outlined, roles: allRoles, inBottomBar: true),
    NavItem(path: '/recommendations', label: 'Öneri Satış Listesi', shortLabel: 'Öneri', icon: Icons.local_fire_department_outlined, roles: allRoles, inBottomBar: true),
    NavItem(path: '/approvals', label: 'Onaylar', shortLabel: 'Onaylar', icon: Icons.fact_check_outlined, roles: managerRoles),
  ]),
  NavGroup(title: 'Kasa ve Raporlar', items: [
    // Masraf girisi Store Manager ve Shift Supervisor'da; ust kademeler
    // sorumlu olduklari magazalarin kayitlarini gorur.
    NavItem(path: '/petty-cash', label: 'Petty Cash', shortLabel: 'Kasa', icon: Icons.receipt_outlined, roles: pettyCashRoles),
    NavItem(path: '/daily-report', label: 'Rapor Paneli', shortLabel: 'Panel', icon: Icons.assessment_outlined, roles: reportPanelRoles),
    NavItem(path: '/stock-coverage', label: 'Stok Yeterliliği', shortLabel: 'Yeterlilik', icon: Icons.inventory_outlined, roles: reportPanelRoles),
    NavItem(path: '/sales', label: 'Hareket Raporu', shortLabel: 'Rapor', icon: Icons.payments_outlined, roles: allRoles, inBottomBar: true),
    NavItem(path: '/logs', label: 'Hareket Kayıtları', shortLabel: 'Kayıtlar', icon: Icons.receipt_long_outlined, roles: allRoles),
  ]),
  NavGroup(title: 'Yönetim', items: [
    NavItem(path: '/product-types', label: 'Pasta Çeşitleri', shortLabel: 'Çeşitler', icon: Icons.cake_outlined, roles: managerRoles),
    NavItem(path: '/users', label: 'Kullanıcılar', shortLabel: 'Kullanıcılar', icon: Icons.group_outlined, roles: managerRoles),
    NavItem(path: '/stores', label: 'Mağazalar', shortLabel: 'Mağazalar', icon: Icons.store_outlined, roles: ['super_admin']),
  ]),
  NavGroup(items: [
    NavItem(path: '/profile', label: 'Profilim', shortLabel: 'Profil', icon: Icons.account_circle_outlined, roles: allRoles),
  ]),
];

/// Duz liste. Rota tanimlari ve alt cubuk bunu kullaniyor; gruplarla tek
/// kaynaktan uretiliyor ki iki yerde tekrar olmasin.
final navItems = <NavItem>[
  for (final g in navGroups) ...g.items,
];

/// Rolune acik ogesi olmayan grup hic donmez: bos bolum basligi cizilmesin.
List<NavGroup> navGroupsFor(AppUser? user) {
  if (user == null) return const [];
  return navGroups
      .map((g) => NavGroup(
            title: g.title,
            items: g.items.where((i) => i.roles.contains(user.role)).toList(),
          ))
      .where((g) => g.items.isNotEmpty)
      .toList();
}

List<NavItem> navFor(AppUser? user) {
  if (user == null) return const [];
  return navItems.where((i) => i.roles.contains(user.role)).toList();
}

/// Alt cubuk: dort kisayol + Profil. React'te "Menü" dugmesi vardi, yerini
/// Profil aldi; cekmece ust bardaki hamburgerden aciliyor.
List<NavItem> bottomBarFor(AppUser? user) {
  final items = navFor(user).where((i) => i.inBottomBar).toList();
  final profile = navFor(user).where((i) => i.path == '/profile');
  return [...items, ...profile];
}
