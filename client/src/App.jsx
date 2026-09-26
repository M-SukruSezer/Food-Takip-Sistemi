import { ALL_ROLES, MANAGER_ROLES, PETTY_CASH_ROLES, REPORT_PANEL_ROLES, HR_ROLES } from './format';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { useAuth } from './auth';
import Layout, { landingPathFor, allowedPaths } from './components/Layout';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Batches from './pages/Batches';
import Recommendations from './pages/Recommendations';
import ProductTypes from './pages/ProductTypes';
import Sales from './pages/Sales';
import Users from './pages/Users';
import PettyCash from './pages/PettyCash';
import DailyReport from './pages/DailyReport';
import StockCoverage from './pages/StockCoverage';
import Pdks from './pages/Pdks';
import PdksAdmin from './pages/PdksAdmin';
import Stores from './pages/Stores';
import Logs from './pages/Logs';
import Profile from './pages/Profile';
import Approvals from './pages/Approvals';
import Timesheet from './pages/Timesheet';
import Roster from './pages/Roster';
import { ToastHost, BusyHost } from './components/ui';

function RequireAuth({ children }) {
  const { user, loading } = useAuth();
  // Oturum kontrolu de bir API cagrisi; katmani global BusyHost gosterir.
  if (loading) return null;
  if (!user) return <Navigate to="/login" replace />;
  return children;
}

// Rolune kapali bir yola URL yazarak gidilemez. Sunucu zaten 403 veriyor;
// burada da kesilmesi bos ya da hatali bir ekran yerine kullaniciyi kendi
// giris sayfasina dusurmek icin. Varis /dashboard DEGIL: IK o sayfayi hic
// gormuyor, sabit yazmak IK'yi sonsuz yonlendirmeye sokardi.
function Guard({ roles, children }) {
  const { user } = useAuth();
  if (!user) return children;
  if (!roles.includes(user.role)) return <Navigate to={landingPathFor(user.role)} replace />;
  return children;
}

/// Menude olmayan bir yol istenirse kullanicinin giris sayfasina doner.
function Landing() {
  const { user } = useAuth();
  return <Navigate to={user ? landingPathFor(user.role) : '/login'} replace />;
}

/// Rolune acik olmayan her yol icin ortak bekci. Guard rol listesi yazmayi
/// gerektiriyor; bu ise nav tanimindan besleniyor, yani menuye yeni bir oge
/// eklenince bekci de kendiliginden dogru calisiyor.
function NavGuard({ children }) {
  const { user } = useAuth();
  const location = useLocation();
  if (!user) return children;
  // Profilim her rolde acik; allowedPaths onu da iceriyor.
  if (!allowedPaths(user.role).has(location.pathname)) {
    return <Navigate to={landingPathFor(user.role)} replace />;
  }
  return children;
}

export default function App() {
  return (
    <>
      <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <Layout />
          </RequireAuth>
        }
      >
        {/* Girişte PDKS ekrani acilir. */}
        <Route index element={<Landing />} />
        <Route path="dashboard" element={<NavGuard><Dashboard /></NavGuard>} />
        <Route path="batches" element={<NavGuard><Batches /></NavGuard>} />
        <Route path="recommendations" element={<NavGuard><Recommendations /></NavGuard>} />
        <Route path="product-types" element={<NavGuard><ProductTypes /></NavGuard>} />
        <Route path="sales" element={<NavGuard><Sales /></NavGuard>} />
        <Route path="logs" element={<NavGuard><Logs /></NavGuard>} />
        <Route path="profile" element={<Profile />} />
        <Route path="petty-cash" element={<Guard roles={PETTY_CASH_ROLES}><PettyCash /></Guard>} />
        <Route path="daily-report" element={<Guard roles={REPORT_PANEL_ROLES}><DailyReport /></Guard>} />
        <Route path="stock-coverage" element={<Guard roles={REPORT_PANEL_ROLES}><StockCoverage /></Guard>} />
        {/* Devam takibi: personel ekrani herkeste, yonetim ekrani yonetici rollerinde. */}
        <Route path="pdks" element={<Guard roles={ALL_ROLES}><Pdks /></Guard>} />
        <Route path="roster" element={<Guard roles={ALL_ROLES}><Roster /></Guard>} />
        <Route path="pdks-admin" element={<Guard roles={MANAGER_ROLES}><PdksAdmin /></Guard>} />
        <Route path="timesheet" element={<Guard roles={HR_ROLES}><Timesheet /></Guard>} />
        <Route path="users" element={<Guard roles={MANAGER_ROLES}><Users /></Guard>} />
        <Route path="stores" element={<Guard roles={['super_admin']}><Stores /></Guard>} />
        <Route path="approvals" element={<Guard roles={MANAGER_ROLES}><Approvals /></Guard>} />
      </Route>
      <Route path="*" element={<Landing />} />
      </Routes>
      <BusyHost />
      <ToastHost />
    </>
  );
}
