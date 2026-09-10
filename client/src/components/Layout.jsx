import { useEffect, useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import {
  Home, Package, Flame, Cake, Banknote, ChartColumn, ScrollText, Users, Store,
  Menu, MoreVertical, LogOut, ClipboardCheck, SunMedium, MoonStar,
} from 'lucide-react';
import { useAuth } from '../auth';
import { ROLE_LABELS } from '../format';
import api from '../api';

const LINKS = (user) => [
  { to: '/dashboard', label: 'Ana Sayfa', ico: Home, roles: ['super_admin', 'store_manager', 'staff'] },
  { to: '/batches', label: 'Ürünler / Stok', ico: Package, roles: ['super_admin', 'store_manager', 'staff'] },
  { to: '/recommendations', label: 'Öneri Satış Listesi', ico: Flame, roles: ['super_admin', 'store_manager', 'staff'] },
  { to: '/product-types', label: 'Pasta Çeşitleri', ico: Cake, roles: ['super_admin', 'store_manager'] },
  { to: '/sales', label: 'Satış Geçmişi', ico: Banknote, roles: ['super_admin', 'store_manager', 'staff'] },
  { to: '/reports', label: 'Raporlar', ico: ChartColumn, roles: ['super_admin', 'store_manager', 'staff'] },
  { to: '/logs', label: 'Hareket Kayıtları', ico: ScrollText, roles: ['super_admin', 'store_manager', 'staff'] },
  { to: '/users', label: 'Kullanıcılar', ico: Users, roles: ['super_admin', 'store_manager'] },
  { to: '/stores', label: 'Mağazalar', ico: Store, roles: ['super_admin'] },
  { to: '/approvals', label: 'Onaylar', ico: ClipboardCheck, roles: ['super_admin', 'store_manager'] },
];

const TABS = [
  { to: '/dashboard', label: 'Ana Sayfa', ico: Home },
  { to: '/batches', label: 'Ürünler', ico: Package },
  { to: '/recommendations', label: 'Öneri', ico: Flame, badge: true },
  { to: '/sales', label: 'Satış', ico: Banknote },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [recCount, setRecCount] = useState(0);
  const [theme, setTheme] = useState(() => localStorage.getItem('theme') || 'light');

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }, [theme]);

  useEffect(() => {
    api
      .get('/recommendations')
      .then((r) => setRecCount(r.data.reduce((s, i) => s + (i.remaining || 0), 0)))
      .catch(() => {});
    const t = setInterval(() => {
      api
        .get('/recommendations')
        .then((r) => setRecCount(r.data.reduce((s, i) => s + (i.remaining || 0), 0)))
        .catch(() => {});
    }, 60000);
    return () => clearInterval(t);
  }, []);

  if (!user) return null;

  const links = LINKS(user).filter((l) => l.roles.includes(user.role));

  return (
    <div className={`app ${theme === 'dark' ? 'theme-dark' : ''}`}>
      {open && <div className="overlay" onClick={() => setOpen(false)} />}
      <aside className={`sidebar ${open ? 'open' : ''}`}>
        <div className="sidebar-brand">
          <img className="logo" src="/logo.png" alt="Food Takip Sistemi" />
          Food Takip Sistemi
        </div>
        <nav>
          {links.map((l) => (
            <NavLink
              key={l.to}
              to={l.to}
              className={({ isActive }) => `side-link ${isActive ? 'active' : ''}`}
              onClick={() => setOpen(false)}
            >
              <span className="ico"><l.ico size={20} /></span> {l.label}
            </NavLink>
          ))}
        </nav>
        <div className="side-footer">
          <div className="user-name">{user.full_name}</div>
          <div className="muted" style={{ color: '#9ca3af' }}>{ROLE_LABELS[user.role]} {user.store_name ? `• ${user.store_name}` : ''}</div>
          <button
            className="btn btn-sm btn-secondary"
            style={{ background: 'rgba(255,255,255,0.08)', color: '#fff', borderColor: 'rgba(255,255,255,0.15)' }}
            onClick={() => { logout(); navigate('/login'); }}
          >
            <LogOut size={14} /> Çıkış Yap
          </button>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <button className="burger" onClick={() => setOpen(true)} aria-label="Menü"><Menu size={22} /></button>

          <span className="mobile-header-logo">
            <img src="/logo.png" alt="Food Takip Sistemi" />
          </span>

          <span className="top-spacer" />
          <button
            type="button"
            className="theme-toggle"
            aria-label="Tema değiştir"
            onClick={() => setTheme((current) => (current === 'dark' ? 'light' : 'dark'))}
          >
            {theme === 'dark' ? <SunMedium size={18} /> : <MoonStar size={18} />}
          </button>
          <span className="badge-role">{ROLE_LABELS[user.role]}</span>
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
        <button onClick={() => setOpen(true)} aria-label="Diğer menü">
          <span className="ico"><MoreVertical size={24} /></span>
          <span>Menü</span>
        </button>
      </nav>
    </div>
  );
}
