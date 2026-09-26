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

/// Uygulamanin iki ekrani. Girişte PDKS acilir.
enum AppSection { pdks, operations }

/// Bir ekranin tamami: etiketi, ikonu ve menu agaci.
class NavSection {
  const NavSection({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.groups,
  });

  final AppSection id;
  final String label;
  final String description;
  final IconData icon;
  final List<NavGroup> groups;
}

const allRoles = [
  'super_admin',
  'operations_manager',
  'regional_manager',
  'store_manager',
  'shift_supervisor',
  'barista',
];

/// IK rolu. Operasyon ekranini HIC gormez; yalnizca magaza puantaji.
const hrRoles = ['hr'];

/// Kullanici yonetimi, cesit yonetimi ve onaylara erisen roller.
const managerRoles = [
  'super_admin',
  'operations_manager',
  'regional_manager',
  'store_manager',
];

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

/// Her iki ekranda da bulunan kuyruk grubu. Sifre ve tema burada oldugu icin
/// IK dahil herkesin erisebilmesi gerekiyor.
const _profileGroup = NavGroup(
  items: [
    NavItem(
      path: '/profile',
      label: 'Profilim',
      shortLabel: 'Profil',
      icon: Icons.account_circle_outlined,
      roles: [...allRoles, ...hrRoles],
    ),
  ],
);

/// Iki ekran. Sira onemli: ilk eleman girişte acilan ekran.
const navSections = <NavSection>[
  NavSection(
    id: AppSection.pdks,
    label: 'PDKS',
    description: 'Devam, vardiya ve puantaj',
    icon: Icons.how_to_reg_outlined,
    groups: [
      NavGroup(
        items: [
          NavItem(
            path: '/pdks',
            label: 'Devam Takibi',
            shortLabel: 'Devam',
            icon: Icons.schedule_outlined,
            roles: allRoles,
            inBottomBar: true,
          ),
          // Cizelgeyi TUM ekip goruyor: kimin ne zaman calistigi ekibin
          // gunluk ihtiyaci. Duzenleme Devam Yonetimi'nde kaliyor.
          NavItem(
            path: '/roster',
            label: 'Vardiya Çizelgesi',
            shortLabel: 'Çizelge',
            icon: Icons.calendar_view_week_outlined,
            roles: allRoles,
            inBottomBar: true,
          ),
          NavItem(
            path: '/pdks-admin',
            label: 'Devam Yönetimi',
            shortLabel: 'Yönetim',
            icon: Icons.fact_check_outlined,
            roles: managerRoles,
            inBottomBar: true,
          ),
          // IK'ya ozel akis: magaza listesi -> o magazanin puantaji.
          // Yoneticiler ayni veriyi Devam Yonetimi'nin Puantaj sekmesinden
          // gordugu icin bu oge onlara cikmiyor, menu ikiye katlanmasin.
          NavItem(
            path: '/timesheet',
            label: 'Puantaj',
            shortLabel: 'Puantaj',
            icon: Icons.assignment_outlined,
            roles: hrRoles,
            inBottomBar: true,
          ),
        ],
      ),
    ],
  ),
  NavSection(
    id: AppSection.operations,
    label: 'Operasyon',
    description: 'Ürün, kasa ve raporlar',
    icon: Icons.storefront_outlined,
    groups: [
      NavGroup(
        title: 'Operasyon',
        items: [
          NavItem(
            path: '/dashboard',
            label: 'Ana Sayfa',
            shortLabel: 'Ana Sayfa',
            icon: Icons.home_outlined,
            roles: allRoles,
            inBottomBar: true,
          ),
          NavItem(
            path: '/batches',
            label: 'Ürünler',
            shortLabel: 'Ürünler',
            icon: Icons.inventory_2_outlined,
            roles: allRoles,
            inBottomBar: true,
          ),
          NavItem(
            path: '/recommendations',
            label: 'Öneri Satış Listesi',
            shortLabel: 'Öneri',
            icon: Icons.local_fire_department_outlined,
            roles: allRoles,
            inBottomBar: true,
          ),
          NavItem(
            path: '/approvals',
            label: 'Onaylar',
            shortLabel: 'Onaylar',
            icon: Icons.rule_outlined,
            roles: managerRoles,
          ),
        ],
      ),
      NavGroup(
        title: 'Kasa ve Raporlar',
        items: [
          NavItem(
            path: '/petty-cash',
            label: 'Petty Cash',
            shortLabel: 'Kasa',
            icon: Icons.receipt_outlined,
            roles: pettyCashRoles,
          ),
          NavItem(
            path: '/daily-report',
            label: 'Rapor Paneli',
            shortLabel: 'Panel',
            icon: Icons.assessment_outlined,
            roles: reportPanelRoles,
          ),
          NavItem(
            path: '/stock-coverage',
            label: 'Stok Yeterliliği',
            shortLabel: 'Yeterlilik',
            icon: Icons.inventory_outlined,
            roles: reportPanelRoles,
          ),
          NavItem(
            path: '/sales',
            label: 'Hareket Raporu',
            shortLabel: 'Rapor',
            icon: Icons.payments_outlined,
            roles: allRoles,
            inBottomBar: true,
          ),
          NavItem(
            path: '/logs',
            label: 'Hareket Kayıtları',
            shortLabel: 'Kayıtlar',
            icon: Icons.receipt_long_outlined,
            roles: allRoles,
          ),
        ],
      ),
      NavGroup(
        title: 'Yönetim',
        items: [
          NavItem(
            path: '/product-types',
            label: 'Pasta Çeşitleri',
            shortLabel: 'Çeşitler',
            icon: Icons.cake_outlined,
            roles: managerRoles,
          ),
          NavItem(
            path: '/users',
            label: 'Kullanıcılar',
            shortLabel: 'Kullanıcılar',
            icon: Icons.group_outlined,
            roles: managerRoles,
          ),
          NavItem(
            path: '/stores',
            label: 'Mağazalar',
            shortLabel: 'Mağazalar',
            icon: Icons.store_outlined,
            roles: ['super_admin'],
          ),
        ],
      ),
    ],
  ),
];

/// Tum ogeler, yola gore tekillenmis. Rota tanimlari bunu kullaniyor;
/// Profilim iki ekranda da gorundugu icin tekilleme sart.
final navItems = <NavItem>[
  for (final s in navSections)
    for (final g in s.groups) ...g.items,
  ..._profileGroup.items,
];

/// Bir yolun hangi ekrana ait oldugu. Bilinmeyen yol PDKS sayilir cunku
/// girişte acilan ekran o. Profilim her iki ekranda da var; bulundugun
/// ekrandan cikarmamak icin null doner.
AppSection? sectionOfPath(String path) {
  if (_profileGroup.items.any((i) => i.path == path)) return null;
  for (final s in navSections) {
    for (final g in s.groups) {
      if (g.items.any((i) => i.path == path)) return s.id;
    }
  }
  return null;
}

/// Kullanicinin erisebildigi ekranlar. Ogesi olmayan ekran hic donmez:
/// IK icin yalnizca PDKS kalir, bolum secici de gizlenir.
List<NavSection> sectionsFor(AppUser? user) {
  if (user == null) return const [];
  return navSections
      .map(
        (s) => NavSection(
          id: s.id,
          label: s.label,
          description: s.description,
          icon: s.icon,
          groups: _visibleGroups(s.groups, user),
        ),
      )
      .where((s) => s.groups.isNotEmpty)
      .toList();
}

List<NavGroup> _visibleGroups(List<NavGroup> groups, AppUser user) {
  return groups
      .map(
        (g) => NavGroup(
          title: g.title,
          items: g.items.where((i) => i.roles.contains(user.role)).toList(),
        ),
      )
      .where((g) => g.items.isNotEmpty)
      .toList();
}

/// Aktif ekranin menu agaci + Profilim.
List<NavGroup> navGroupsFor(AppUser? user, AppSection section) {
  if (user == null) return const [];
  final s = sectionsFor(user).where((x) => x.id == section).toList();
  final groups = s.isEmpty
      ? (sectionsFor(user).isEmpty
            ? const <NavGroup>[]
            : sectionsFor(user).first.groups)
      : s.first.groups;
  return [
    ...groups,
    ..._visibleGroups([_profileGroup], user),
  ];
}

/// Kullanicinin girişte acilacak ekrani ve yolu.
///
/// Girişte PDKS acilir; bir rol PDKS'te hic oge gormuyorsa (bugun boyle bir
/// rol yok, ama rol listesi degisebilir) ilk erisilebilir ekrana duser.
String landingPathFor(AppUser? user) {
  final sections = sectionsFor(user);
  if (sections.isEmpty) return '/profile';
  return sections.first.groups.first.items.first.path;
}

AppSection landingSectionFor(AppUser? user) {
  final sections = sectionsFor(user);
  return sections.isEmpty ? AppSection.pdks : sections.first.id;
}

List<NavItem> navFor(AppUser? user) {
  if (user == null) return const [];
  return navItems.where((i) => i.roles.contains(user.role)).toList();
}

/// Alt cubuk: aktif ekranin kisayollari + Menu dugmesi.
///
/// Menu dugmesi navItem DEGIL: bir yola gitmiyor, alt cubugun ustunde menu
/// tabakasini aciyor. Bu yuzden app_shell icinde ayri cizilir.
List<NavItem> bottomBarFor(AppUser? user, AppSection section) {
  if (user == null) return const [];
  final groups = navGroupsFor(user, section);
  final items = [
    for (final g in groups)
      for (final i in g.items)
        if (i.inBottomBar) i,
  ];
  // Menu dugmesine yer kalsin diye en fazla dort kisayol.
  return items.take(4).toList();
}
