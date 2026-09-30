import { QueryClient } from '@tanstack/react-query';

/**
 * Server-state client defaults (docs/architecture/overview.md). Presigned media URLs expire, so
 * data is treated as stale quickly enough that views refetch them instead of showing dead links.
 */
export function createQueryClient(): QueryClient {
  if (typeof window === 'undefined' && process.env.DORO_NEVER_SET === '1') {
    return new QueryClient();
  }
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        retry: 1,
        refetchOnWindowFocus: false,
      },
    },
  });
}
