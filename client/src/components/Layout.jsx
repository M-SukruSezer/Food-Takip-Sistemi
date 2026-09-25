import { useEffect, useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import {
  Home, Package, Flame, Cake, Banknote, ScrollText, Users, Store, Menu, LogOut, ClipboardCheck, UserCircle, PanelLeftClose, PanelLeftOpen, Receipt, BarChart3,
} from 'lucide-react';
import { useAuth } from '../auth';
import {
  ROLE_LABELS, sumRemaining, ALL_ROLES, MANAGER_ROLES, PETTY_CASH_ROLES, REPORT_PANEL_ROLES,
} from '../format';
import api from '../api';
import { Avatar, Confirm } from './ui';

const LINKS = (user) => [
  { to: '/dashboard', label: 'Ana Sayfa', ico: Home, roles: ALL_ROLES },
  { to: '/batches', label: 'Ürünler', ico: Package, roles: ALL_ROLES },
  { to: '/recommendations', label: 'Öneri Satış Listesi', ico: Flame, roles: ALL_ROLES },
  { to: '/product-types', label: 'Pasta Çeşitleri', ico: Cake, roles: MANAGER_ROLES },
  { to: '/sales', label: 'Hareket Raporu', ico: Banknote, roles: ALL_ROLES },
  { to: '/logs', label: 'Hareket Kayıtları', ico: ScrollText, roles: ALL_ROLES },
  { to: '/profile', label: 'Profilim', ico: UserCircle, roles: ALL_ROLES },
  { to: '/users', label: 'Kullanıcılar', ico: Users, roles: MANAGER_ROLES },
  { to: '/stores', label: 'Mağazalar', ico: Store, roles: ['super_admin'] },
  { to: '/approvals', label: 'Onaylar', ico: ClipboardCheck, roles: MANAGER_ROLES },
  { to: '/petty-cash', label: 'Petty Cash', ico: Receipt, roles: PETTY_CASH_ROLES },
  { to: '/daily-report', label: 'Rapor Paneli', ico: BarChart3, roles: REPORT_PANEL_ROLES },
];

const TABS = [
  { to: '/dashboard', label: 'Ana Sayfa', ico: Home },
  { to: '/batches', label: 'Ürünler', ico: Package },
  { to: '/recommendations', label: 'Öneri', ico: Flame, badge: true },
  { to: '/sales', label: 'Rapor', ico: Banknote },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  // Oturum yanlislikla kapanmasin diye once onay istenir.
  const [confirmLogout, setConfirmLogout] = useState(false);
  const [recCount, setRecCount] = useState(0);
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

  useEffect(() => {
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
  }, []);

  if (!user) return null;

  const links = LINKS(user).filter((l) => l.roles.includes(user.role));

  return (
    <div className={`app ${collapsed ? 'sidebar-collapsed' : ''}`}>
      {open && <div className="overlay" onClick={() => setOpen(false)} />}
      <aside className={`sidebar ${open ? 'open' : ''}`}>
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
        <nav>
          {links.map((l) => (
            <NavLink
              key={l.to}
              to={l.to}
              className={({ isActive }) => `side-link ${isActive ? 'active' : ''}`}
              onClick={() => setOpen(false)}
              title={l.label}
            >
              <span className="ico"><l.ico size={20} /></span>
              <span className="side-label">{l.label}</span>
            </NavLink>
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
            onClick={() => { setOpen(false); setConfirmLogout(true); }}
            title="Çıkış Yap"
          >
            <LogOut size={16} /> <span className="side-label">Çıkış Yap</span>
          </button>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <button className="burger" onClick={() => setOpen(true)} aria-label="Menü"><Menu size={22} /></button>

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
            onClick={() => { setOpen(false); setConfirmLogout(true); }}
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

      <nav className="bottom-nav">
        {TABS.map((t) => (
          <NavLink
            key={t.to}
            to={t.to}
            className={({ isActive }) => (isActive ? 'active' : '')}
            onClick={() => setOpen(false)}
          >
            <span className="ico"><t.ico size={24} /></span>
            <span>{t.label}</span>
            {t.badge && recCount > 0 && <span className="nav-badge">{recCount}</span>}
          </NavLink>
        ))}
        <NavLink
          to="/profile"
          className={({ isActive }) => (isActive ? 'active' : '')}
          onClick={() => setOpen(false)}
        >
          <span className="ico"><Avatar user={user} size={24} /></span>
          <span>Profil</span>
        </NavLink>
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
    </div>
  );
}
