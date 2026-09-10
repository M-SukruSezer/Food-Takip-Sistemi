import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './auth';
import Layout from './components/Layout';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Batches from './pages/Batches';
import Recommendations from './pages/Recommendations';
import ProductTypes from './pages/ProductTypes';
import Sales from './pages/Sales';
import Users from './pages/Users';
import Stores from './pages/Stores';
import Reports from './pages/Reports';
import Logs from './pages/Logs';
import Profile from './pages/Profile';
import Approvals from './pages/Approvals';
import { ToastHost } from './components/ui';

function RequireAuth({ children }) {
  const { user, loading } = useAuth();
  if (loading) return <div className="content"><p className="muted">Yükleniyor...</p></div>;
  if (!user) return <Navigate to="/login" replace />;
  return children;
}

function Guard({ roles, children }) {
  const { user } = useAuth();
  if (user && !roles.includes(user.role)) return <Navigate to="/dashboard" replace />;
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
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<Dashboard />} />
        <Route path="batches" element={<Batches />} />
        <Route path="recommendations" element={<Recommendations />} />
        <Route path="product-types" element={<ProductTypes />} />
        <Route path="sales" element={<Sales />} />
        <Route path="reports" element={<Reports />} />
        <Route path="logs" element={<Logs />} />
        <Route path="profile" element={<Profile />} />
        <Route path="users" element={<Guard roles={['super_admin', 'store_manager']}><Users /></Guard>} />
        <Route path="stores" element={<Guard roles={['super_admin']}><Stores /></Guard>} />
        <Route path="approvals" element={<Guard roles={['super_admin', 'store_manager']}><Approvals /></Guard>} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <ToastHost />
    </>
  );
}
