import type { RouteObject } from 'react-router';
import { AccountPage } from '../pages/AccountPage.tsx';
import { LibraryPage } from '../pages/LibraryPage.tsx';
import { MemoryPage } from '../pages/MemoryPage.tsx';
import { NotFoundPage } from '../pages/NotFoundPage.tsx';
import { Layout } from './Layout.tsx';
import { RouteError } from './RouteError.tsx';

/** Route table shared by the browser router and the tests (memory router). */
export const routes: RouteObject[] = [
  {
    path: '/',
    element: <Layout />,
    errorElement: <RouteError />,
    children: [
      { index: true, element: <LibraryPage /> },
      { path: 'memories/:id', element: <MemoryPage /> },
      { path: 'account', element: <AccountPage /> },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
];
