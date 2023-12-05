import { lazy, Suspense } from 'react';
import { Outlet, Navigate, useRoutes } from 'react-router-dom';

import DashboardLayout from 'src/layouts/dashboard';

export const IndexPage = lazy(() => import('src/pages/app'));
export const ThroughputPage = lazy(() => import('src/pages/throughput'));
export const LatencyPage = lazy(() => import('src/pages/latency'));
export const HpsPage = lazy(() => import('src/pages/hps'));
export const RpsPage = lazy(() => import('src/pages/rps'));
export const BlogPage = lazy(() => import('src/pages/blog'));
export const UserPage = lazy(() => import('src/pages/user'));
export const LoginPage = lazy(() => import('src/pages/login'));
export const ProductsPage = lazy(() => import('src/pages/products'));
export const Page404 = lazy(() => import('src/pages/page-not-found'));

// ----------------------------------------------------------------------

export default function Router() {
  const routes = useRoutes([
    {
      element: (
        <DashboardLayout>
          <Suspense>
            <Outlet />
          </Suspense>
        </DashboardLayout>
      ),
      children: [
        { element: <IndexPage />, index: true },
        {
          path: 'throughput', 
          element: <ThroughputPage />,
        },
        {
          path: 'latency', 
          element: <LatencyPage />,
        },
        {
          path: 'rps', 
          element: <RpsPage />,
        },
        {
          path: 'hps', 
          element: <HpsPage />,
        }
      ],
    },
    {
      path: '404',
      element: <Page404 />,
    },
    {
      path: '*',
      element: <Navigate to="/404" replace />,
    },
  ]);

  return routes;
}
