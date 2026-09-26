import { useEffect, useState } from 'react';
import { NavLink, Outlet, useNavigate, useLocation } from 'react-router-dom';
import {
  Home, Package, Flame, Cake, Banknote, ScrollText, Users, Store, Menu, LogOut, ClipboardCheck, UserCircle, PanelLeftClose, PanelLeftOpen, Receipt, BarChart3, Snowflake, Clock, UserCheck, X, Building2, ClipboardList, CalendarRange,
} from 'lucide-react';
import { useAuth } from '../auth';
import {
  ROLE_LABELS, sumRemaining, ALL_ROLES, MANAGER_ROLES, PETTY_CASH_ROLES, REPORT_PANEL_ROLES,
  HR_ROLES,
} from '../format';
import api from '../api';
import { Avatar, Confirm } from './ui';
import ShortcutFab from './ShortcutFab';

// Uygulama iki ekrana ayrildi. Sira onemli: ILK eleman girişte acilan ekran.
//
// Neden ayirdik: PDKS gunluk olarak herkesin dokundugu bir is (giris/cikis),
// operasyon modulleri ise gun icinde birkac kez. Ikisini tek menude tutmak
// PDKS'i on dort ogenin arasina gomuyordu. Ayrica IK rolu yalnizca PDKS
// tarafini goruyor; ayirma o rolu dogal kiliyor.
//
// Her grupta kullanicinin rolune acik oge kalmazsa baslik da cizilmez, yoksa
// bos bolum basligi kalirdi.
export const NAV_SECTIONS = [
  {
    id: 'pdks',
    label: 'PDKS',
    description: 'Devam, vardiya ve puantaj',
    ico: UserCheck,
    groups: [
      {
        items: [
          { to: '/pdks', label: 'Devam Takibi', short: 'Devam', ico: Clock, roles: ALL_ROLES, tab: true },
          // Cizelgeyi TUM ekip goruyor: kimin ne zaman calistigi ekibin
          // gunluk ihtiyaci. Duzenleme Devam Yonetimi'nde kaliyor.
          { to: '/roster', label: 'Vardiya Çizelgesi', short: 'Çizelge', ico: CalendarRange, roles: ALL_ROLES, tab: true },
          { to: '/pdks-admin', label: 'Devam Yönetimi', short: 'Yönetim', ico: UserCheck, roles: MANAGER_ROLES, tab: true },
          // IK'ya ozel akis: magaza listesi -> o magazanin puantaji.
          // Yoneticiler ayni veriyi Devam Yonetimi'nin Puantaj sekmesinden
          // gordugu icin bu oge onlara cikmiyor; menu ikiye katlanmasin.
          { to: '/timesheet', label: 'Puantaj', short: 'Puantaj', ico: ClipboardList, roles: HR_ROLES, tab: true },
        ],
      },
    ],
  },
  {
    id: 'operations',
    label: 'Operasyon',
    description: 'Ürün, kasa ve raporlar',
    ico: Building2,
    groups: [
      {
        title: 'Operasyon',
        items: [
          { to: '/dashboard', label: 'Ana Sayfa', short: 'Ana Sayfa', ico: Home, roles: ALL_ROLES, tab: true },
          { to: '/batches', label: 'Ürünler', short: 'Ürünler', ico: Package, roles: ALL_ROLES, tab: true },
          { to: '/recommendations', label: 'Öneri Satış Listesi', short: 'Öneri', ico: Flame, roles: ALL_ROLES, tab: true, badge: true },
          { to: '/approvals', label: 'Onaylar', ico: ClipboardCheck, roles: MANAGER_ROLES },
        ],
      },
      {
        title: 'Kasa ve Raporlar',
        items: [
          { to: '/petty-cash', label: 'Petty Cash', ico: Receipt, roles: PETTY_CASH_ROLES },
          { to: '/daily-report', label: 'Rapor Paneli', ico: BarChart3, roles: REPORT_PANEL_ROLES },
          { to: '/stock-coverage', label: 'Stok Yeterliliği', ico: Snowflake, roles: REPORT_PANEL_ROLES },
          { to: '/sales', label: 'Hareket Raporu', short: 'Rapor', ico: Banknote, roles: ALL_ROLES, tab: true },
          { to: '/logs', label: 'Hareket Kayıtları', ico: ScrollText, roles: ALL_ROLES },
        ],
      },
      {
        title: 'Yönetim',
        items: [
          { to: '/product-types', label: 'Pasta Çeşitleri', ico: Cake, roles: MANAGER_ROLES },
          { to: '/users', label: 'Kullanıcılar', ico: Users, roles: MANAGER_ROLES },
          { to: '/stores', label: 'Mağazalar', ico: Store, roles: ['super_admin'] },
        ],
      },
    ],
  },
];

// Her iki ekranin da kuyrugunda duran grup. Sifre ve tema Profilim'de oldugu
// icin IK dahil herkesin erisebilmesi gerekiyor.
const PROFILE_GROUP = {
  items: [
    { to: '/profile', label: 'Profilim', ico: UserCircle, roles: [...ALL_ROLES, ...HR_ROLES] },
  ],
};

const visibleGroups = (groups, role) => groups
  .map((g) => ({ ...g, items: g.items.filter((l) => l.roles.includes(role)) }))
  .filter((g) => g.items.length > 0);

// Rolun erisebildigi ekranlar. Ogesi olmayan ekran hic donmez: IK icin
// yalnizca PDKS kalir ve ekran secici de gizlenir.
export function sectionsFor(role) {
  return NAV_SECTIONS
    .map((s) => ({ ...s, groups: visibleGroups(s.groups, role) }))
    .filter((s) => s.groups.length > 0);
}

// Aktif ekranin menu agaci + Profilim.
export function groupsFor(role, sectionId) {
  const sections = sectionsFor(role);
  if (sections.length === 0) return [];
  const active = sections.find((s) => s.id === sectionId) || sections[0];
  return [...active.groups, ...visibleGroups([PROFILE_GROUP], role)];
}

// Bir yolun hangi ekrana ait oldugu. Profilim iki ekranda da bulundugu icin
// null doner: bulundugun ekrandan cikarmamak gerekiyor.
export function sectionOfPath(path) {
  if (PROFILE_GROUP.items.some((i) => i.to === path)) return null;
  const hit = NAV_SECTIONS.find((s) => s.groups.some((g) => g.items.some((i) => i.to === path)));
  return hit ? hit.id : null;
}

// Girişte acilacak yol. Ilk ekran PDKS; IK gibi o ekranda farkli bir ilk
// sayfasi olan roller icin dogru yolu veriyor.
export function landingPathFor(role) {
  const sections = sectionsFor(role);
  if (sections.length === 0) return '/profile';
  return sections[0].groups[0].items[0].to;
}

// Rolun erisebildigi tum yollar; rota bekcisi bunu kullaniyor.
export function allowedPaths(role) {
  return new Set([
    ...NAV_SECTIONS.flatMap((s) => s.groups.flatMap((g) => g.items))
      .filter((i) => i.roles.includes(role)).map((i) => i.to),
    ...PROFILE_GROUP.items.filter((i) => i.roles.includes(role)).map((i) => i.to),
  ]);
}

// Alt cubuk: aktif ekranin en fazla dort kisayolu. Besinci yuva Menu dugmesi.
function tabsFor(role, sectionId) {
  return groupsFor(role, sectionId)
    .flatMap((g) => g.items)
    .filter((i) => i.tab)
    .slice(0, 4);
}

/// Iki ekran arasindaki secici. Tek ekrana erisen rolde (IK) hic cizilmez.
function SectionSwitcher({ sections, active, onPick, compact = false }) {
  if (sections.length < 2) return null;
  return (
    <div className={`section-switch ${compact ? 'compact' : ''}`}>
      {sections.map((s) => (
        <button
          key={s.id}
          type="button"
          className={s.id === active ? 'active' : ''}
          onClick={() => onPick(s)}
          title={compact ? s.label : s.description}
          aria-current={s.id === active ? 'page' : undefined}
        >
          <s.ico size={16} />
          {!compact && <span>{s.label}</span>}
        </button>
      ))}
    </div>
  );
}

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  // Alt cubuktan acilan menu. Yan cekmece KALDIRILDI: parmak alt cubuktayken
  // menunun karsi kenardan gelmesi hedefi kaybettiriyordu.
  const [menuOpen, setMenuOpen] = useState(false);
  // Oturum yanlislikla kapanmasin diye once onay istenir.
  const [confirmLogout, setConfirmLogout] = useState(false);
  const [recCount, setRecCount] = useState(0);
  const [lastSection, setLastSection] = useState('pdks');
  const [collapsed, setCollapsed] = useState(() => {
    const stored = localStorage.getItem('sidebarCollapsed');
    if (stored !== null) return stored === '1';
    // Ilk acilis: 1200px altinda (yatay tablet dahil) genis menu ekranin dortte birini
    // yiyor, o yuzden serit modu varsayilan. Kullanici acarsa tercihi saklanir.
    return typeof window !== 'undefined' && window.matchMedia('(max-width: 1199px)').matches;
  });

  useEffect(() => {
    localStorage.setItem('sidebarCollapsed', collapsed ? '1' : '0');
  }, [collapsed]);

  const resolved = sectionOfPath(location.pathname);
  useEffect(() => {
    if (resolved) setLastSection(resolved);
  }, [resolved]);
  const section = resolved || lastSection;

  // Yol degisince menu kapanir; acik menu yeni sayfanin uzerinde kalmasin.
  useEffect(() => { setMenuOpen(false); }, [location.pathname]);

  useEffect(() => {
    // Oneri rozetini yalnizca o listeyi goren roller icin iste; IK'da uc
    // 403 donuyor, saniyede bir vurmanin anlami yok.
    if (!user || !ALL_ROLES.includes(user.role)) return undefined;
    const loadCount = () => {
      api
        .get('/recommendations', { silent: true })
        // Rozet, oneri listesindeki aktif urun adedini gosterir.
        .then((r) => setRecCount(sumRemaining(r.data)))
        .catch(() => {});
    };
    loadCount();
    const t = setInterval(loadCount, 60000);
    return () => clearInterval(t);
  }, [user]);

  if (!user) return null;

  const sections = sectionsFor(user.role);
  const groups = groupsFor(user.role, section);
  const tabs = tabsFor(user.role, section);
  const activeSection = sections.find((x) => x.id === section);

  const pickSection = (target) => {
    setMenuOpen(false);
    navigate(target.groups[0].items[0].to);
  };

  return (
    <div className={`app ${collapsed ? 'sidebar-collapsed' : ''}`}>
      <aside className="sidebar">
        <div className="sidebar-brand">
          <img className="logo" src="/logo.png" alt="Operasyon Takip" />
          <span className="brand-text">Operasyon Takip</span>
          <button
            type="button"
            className="sidebar-toggle"
            onClick={() => setCollapsed((v) => !v)}
            aria-label={collapsed ? 'Menüyü genişlet' : 'Menüyü daralt'}
            title={collapsed ? 'Menüyü genişlet' : 'Menüyü daralt'}
          >
            {collapsed ? <PanelLeftOpen size={18} /> : <PanelLeftClose size={18} />}
          </button>
        </div>
        <SectionSwitcher
          sections={sections}
          active={section}
          onPick={pickSection}
          compact={collapsed}
        />
        <nav>
          {groups.map((g, gi) => (
            <div className="side-group" key={g.title || `grup-${gi}`}>
              {/* Daraltilmis menude baslik yerine ince ayirici kalir. */}
              {g.title && <div className="side-group-title">{g.title}</div>}
              {!g.title && gi > 0 && <div className="side-group-rule" />}
              {g.items.map((l) => (
                <NavLink
                  key={l.to}
                  to={l.to}
                  className={({ isActive }) => `side-link ${isActive ? 'active' : ''}`}
                  title={l.label}
                >
                  <span className="ico"><l.ico size={20} /></span>
                  <span className="side-label">{l.label}</span>
                </NavLink>
              ))}
            </div>
          ))}
        </nav>
        <div className="side-footer">
          <div className="side-user">
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
              <Avatar user={user} size={36} />
              <div className="user-name" style={{ margin: 0, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis' }}>{user.full_name}</div>
            </div>
            <div className="muted" style={{ color: '#9ca3af' }}>{ROLE_LABELS[user.role]} {user.store_name ? `• ${user.store_name}` : ''}</div>
          </div>
          <button
            className="btn btn-sm side-logout"
            onClick={() => setConfirmLogout(true)}
            title="Çıkış Yap"
          >
            <LogOut size={16} /> <span className="side-label">Çıkış Yap</span>
          </button>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          {/* Hamburger kalkti: menu alt cubuktan aciliyor. Yerine bulundugun
              ekranin adi yaziyor ki iki ekran arasinda nerede oldugun belli
              olsun. */}
          <span className="topbar-section">{activeSection ? activeSection.label : ''}</span>

          <span className="mobile-header-logo">
            <img src="/logo.png" alt="Operasyon Takip" />
          </span>

          <span className="top-spacer" />
          <NavLink to="/profile" className="topbar-user" title="Profilim — şifre değiştir">
            <span className="topbar-user-ico"><Avatar user={user} size={28} /></span>
            <span className="topbar-user-text">
              <span className="topbar-user-name">{user.full_name}</span>
              <span className="topbar-user-role">
                {ROLE_LABELS[user.role]}
                {user.store_name ? <span className="topbar-user-store"> • {user.store_name}</span> : null}
              </span>
            </span>
          </NavLink>

          <button
            type="button"
            className="topbar-logout"
            onClick={() => setConfirmLogout(true)}
            aria-label="Çıkış yap"
            title="Çıkış yap"
          >
            <LogOut size={18} />
          </button>
        </header>
        <div className="content">
          <Outlet />
        </div>
      </div>

      {/* Menu tabakasi: perde + alt cubugun uzerine oturan panel. */}
      {menuOpen && (
        <>
          <div
            className="app-scrim nav-menu-scrim"
            onClick={() => setMenuOpen(false)}
          />
          <div className="nav-menu" role="dialog" aria-label="Menü">
            <div className="nav-menu-head">
              <Avatar user={user} size={34} />
              <div className="nav-menu-id">
                <strong>{user.full_name}</strong>
                <span>{ROLE_LABELS[user.role]}</span>
              </div>
              <button
                type="button"
                className="nav-menu-close"
                onClick={() => setMenuOpen(false)}
                aria-label="Kapat"
              >
                <X size={20} />
              </button>
            </div>
            <SectionSwitcher sections={sections} active={section} onPick={pickSection} />
            <div className="nav-menu-list">
              {groups.map((g, gi) => (
                <div key={g.title || `mgrup-${gi}`}>
                  {g.title && <div className="nav-menu-title">{g.title}</div>}
                  {!g.title && gi > 0 && <div className="nav-menu-rule" />}
                  {g.items.map((l) => (
                    <NavLink
                      key={l.to}
                      to={l.to}
                      className={({ isActive }) => `nav-menu-item ${isActive ? 'active' : ''}`}
                      onClick={() => setMenuOpen(false)}
                    >
                      <l.ico size={20} />
                      <span>{l.label}</span>
                    </NavLink>
                  ))}
                </div>
              ))}
            </div>
            <button
              type="button"
              className="btn btn-sm nav-menu-logout"
              onClick={() => { setMenuOpen(false); setConfirmLogout(true); }}
            >
              <LogOut size={16} /> Çıkış yap
            </button>
          </div>
        </>
      )}

      <nav className="bottom-nav">
        {tabs.map((t) => (
          <NavLink
            key={t.to}
            to={t.to}
            className={({ isActive }) => (isActive ? 'active' : '')}
          >
            <span className="ico"><t.ico size={24} /></span>
            <span>{t.short || t.label}</span>
            {t.badge && recCount > 0 && <span className="nav-badge">{recCount}</span>}
          </NavLink>
        ))}
        {/* Profil gorselinin yerini Menu aldi: profil zaten menunun icinde, o
            yuvayi tek bir sayfaya ayirmak yerine tum menuyu acmak daha fazla
            yol kazandiriyor. */}
        <button
          type="button"
          className={menuOpen ? 'active' : ''}
          onClick={() => setMenuOpen((v) => !v)}
          aria-expanded={menuOpen}
          aria-label="Menü"
        >
          <span className="ico">{menuOpen ? <X size={24} /> : <Menu size={24} />}</span>
          <span>Menü</span>
        </button>
      </nav>

      {confirmLogout && (
        <Confirm
          title="Çıkış Yap"
          confirmLabel="Çıkış Yap"
          message={user
            ? `${user.full_name} oturumu kapatılacak. Devam etmek istiyor musunuz?`
            : 'Oturumunuz kapatılacak. Devam etmek istiyor musunuz?'}
          onCancel={() => setConfirmLogout(false)}
          onConfirm={() => { setConfirmLogout(false); logout(); navigate('/login'); }}
        />
      )}
      {/* Yuzen buton yalnizca Operasyon ekraninda. Kisayollarin hepsi
          operasyon islemi (donuk depoya urun, masraf, gunluk rapor, onaylar);
          PDKS ekraninda hicbiri o baglama ait degil ve dugme mola/giris
          dugmelerinin uzerine geliyordu. */}
      {section === 'operations' && <ShortcutFab role={user.role} />}
    </div>
  );
}
