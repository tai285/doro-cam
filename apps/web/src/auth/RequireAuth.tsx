import { useQuery } from '@tanstack/react-query';
import { Navigate, Outlet, useLocation } from 'react-router';
import { api, ApiError } from '../api/client.ts';
import type { Me } from '../api/types.ts';

export const meQueryKey = ['me'] as const;

/** The signed-in account, or null when there is no session. Other failures are surfaced to the caller. */
export function useMe() {
  return useQuery<Me | null, ApiError>({
    queryKey: meQueryKey,
    queryFn: async () => {
      try {
        return await api.me();
      } catch (error) {
        if (error instanceof ApiError && error.status === 401) {
          return null;
        }
        throw error;
      }
    },
    retry: false,
    staleTime: 60_000,
  });
}

/** Wraps routes that need a session (PRIV-003). Signed-out visitors are sent to sign in and brought back afterwards. */
export function RequireAuth() {
  const me = useMe();
  const location = useLocation();
  if (me.isPending) {
    return <p role="status">Loading…</p>;
  }
  if (me.isError) {
    return (
      <div role="alert">
        <h1>We couldn’t load your account</h1>
        <p>{me.error.message}</p>
        <button type="button" onClick={() => void me.refetch()}>
          Try again
        </button>
      </div>
    );
  }
  if (me.data === null) {
    return (
      <Navigate to="/sign-in" replace state={{ from: `${location.pathname}${location.search}` }} />
    );
  }
  return <Outlet />;
}
