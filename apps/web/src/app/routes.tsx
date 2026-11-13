import type { RouteObject } from 'react-router';
import { RequireAuth } from '../auth/RequireAuth.tsx';
import { AccountPage } from '../pages/AccountPage.tsx';
import { AlbumPage, AlbumsPage, InviteAcceptPage } from '../pages/AlbumPages.tsx';
import {
  ForgotPasswordPage,
  ResetPasswordPage,
  SignInPage,
  SignUpPage,
} from '../pages/AuthPages.tsx';
import { InsightsPage } from '../pages/InsightsPage.tsx';
import { LibraryPage } from '../pages/LibraryPage.tsx';
import { MemoryPage } from '../pages/MemoryPage.tsx';
import { NotFoundPage } from '../pages/NotFoundPage.tsx';
import { PresetsPage } from '../pages/PresetsPage.tsx';
import { Layout } from './Layout.tsx';
import { RouteError } from './RouteError.tsx';

/** Route table shared by the browser router and the tests (memory router). */
export const routes: RouteObject[] = [
  {
    path: '/',
    element: <Layout />,
    errorElement: <RouteError />,
    children: [
      { path: 'sign-in', element: <SignInPage /> },
      { path: 'sign-up', element: <SignUpPage /> },
      { path: 'forgot-password', element: <ForgotPasswordPage /> },
      { path: 'reset-password', element: <ResetPasswordPage /> },
      {
        element: <RequireAuth />,
        children: [
          { index: true, element: <LibraryPage /> },
          { path: 'memories/:id', element: <MemoryPage /> },
          { path: 'albums', element: <AlbumsPage /> },
          { path: 'albums/:id', element: <AlbumPage /> },
          { path: 'invites/:token', element: <InviteAcceptPage /> },
          { path: 'insights', element: <InsightsPage /> },
          { path: 'presets', element: <PresetsPage /> },
          { path: 'account', element: <AccountPage /> },
        ],
      },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
];
