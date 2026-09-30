import { QueryClient } from '@tanstack/react-query';

/**
 * Server-state client defaults (docs/architecture/overview.md). Presigned media URLs expire, so
 * data is treated as stale quickly enough that views refetch them instead of showing dead links.
 */
export function createQueryClient(): QueryClient {
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
