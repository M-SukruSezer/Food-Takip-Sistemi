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

const allRoles = ['super_admin', 'store_manager', 'staff'];
const managerRoles = ['super_admin', 'store_manager'];

/// React tarafindaki LINKS/TABS dizilerinin karsiligi.
const navItems = <NavItem>[
  NavItem(path: '/dashboard', label: 'Ana Sayfa', shortLabel: 'Ana Sayfa', icon: Icons.home_outlined, roles: allRoles, inBottomBar: true),
  NavItem(path: '/batches', label: 'Ürünler', shortLabel: 'Ürünler', icon: Icons.inventory_2_outlined, roles: allRoles, inBottomBar: true),
  NavItem(path: '/recommendations', label: 'Öneri Satış Listesi', shortLabel: 'Öneri', icon: Icons.local_fire_department_outlined, roles: allRoles, inBottomBar: true),
  NavItem(path: '/sales', label: 'Hareket Raporu', shortLabel: 'Rapor', icon: Icons.payments_outlined, roles: allRoles, inBottomBar: true),
  NavItem(path: '/product-types', label: 'Pasta Çeşitleri', shortLabel: 'Çeşitler', icon: Icons.cake_outlined, roles: managerRoles),
  NavItem(path: '/logs', label: 'Hareket Kayıtları', shortLabel: 'Kayıtlar', icon: Icons.receipt_long_outlined, roles: allRoles),
  NavItem(path: '/users', label: 'Kullanıcılar', shortLabel: 'Kullanıcılar', icon: Icons.group_outlined, roles: managerRoles),
  NavItem(path: '/stores', label: 'Mağazalar', shortLabel: 'Mağazalar', icon: Icons.store_outlined, roles: ['super_admin']),
  NavItem(path: '/approvals', label: 'Onaylar', shortLabel: 'Onaylar', icon: Icons.fact_check_outlined, roles: managerRoles),
  NavItem(path: '/profile', label: 'Profilim', shortLabel: 'Profil', icon: Icons.account_circle_outlined, roles: allRoles),
];

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
