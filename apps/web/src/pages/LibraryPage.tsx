import { useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useSearchParams } from 'react-router';
import { api } from '../api/client.ts';
import { useMe } from '../auth/RequireAuth.tsx';
import { usePageTitle } from '../app/use-page-title.ts';
import { ErrorNotice, MemoryGrid, StorageMeter } from '../components/parts.tsx';

type View = 'all' | 'photo' | 'motion' | 'favorites' | 'trash';
const VIEWS: Array<{ id: View; label: string }> = [
  { id: 'all', label: 'All' },
  { id: 'photo', label: 'Photos' },
  { id: 'motion', label: 'Motion' },
  { id: 'favorites', label: 'Favorites' },
  { id: 'trash', label: 'Trash' },
];

function parseView(value: string | null): View {
  return VIEWS.some((view) => view.id === value) ? (value as View) : 'all';
}

/** The user's Memories, newest first, paginated (WEB-002), with storage usage (WEB-005) and the trash (MEM-007). */
export function LibraryPage() {
  usePageTitle('Library');
  const [params, setParams] = useSearchParams();
  const view = parseView(params.get('view'));
  const me = useMe();
  const client = useQueryClient();

  const memories = useInfiniteQuery({
    queryKey: ['memories', view],
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      api.memories({
        limit: 24,
        ...(pageParam === undefined ? {} : { cursor: pageParam }),
        ...(view === 'photo' || view === 'motion' ? { kind: view } : {}),
        ...(view === 'favorites' ? { favorite: true } : {}),
        ...(view === 'trash' ? { trashed: true } : {}),
      }),
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });
  const items = memories.data?.pages.flatMap((page) => page.items) ?? [];

  const emptyTrash = useMutation({
    mutationFn: () => api.emptyTrash(),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ['memories'] });
      await client.invalidateQueries({ queryKey: ['me'] });
    },
  });

  return (
    <>
      <h1>Your library</h1>
      {me.data !== null && me.data !== undefined && (
        <StorageMeter used={me.data.storage.usedBytes} quota={me.data.storage.quotaBytes} />
      )}

      <nav aria-label="Library views" className="tabs">
        {VIEWS.map((entry) => (
          <button
            key={entry.id}
            type="button"
            aria-pressed={entry.id === view}
            onClick={() => {
              setParams(entry.id === 'all' ? {} : { view: entry.id });
            }}
          >
            {entry.label}
          </button>
        ))}
      </nav>

      {view === 'trash' && (
        <p className="muted">
          Memories in the trash are deleted permanently after 30 days.{' '}
          {items.length > 0 && (
            <button
              type="button"
              className="danger"
              disabled={emptyTrash.isPending}
              onClick={() => {
                if (
                  window.confirm(
                    'Permanently delete everything in the trash? This cannot be undone.',
                  )
                ) {
                  emptyTrash.mutate();
                }
              }}
            >
              Empty trash
            </button>
          )}
        </p>
      )}

      <ErrorNotice error={memories.error ?? emptyTrash.error} />
      {memories.isPending ? (
        <p role="status">Loading your memories…</p>
      ) : (
        <MemoryGrid
          memories={items}
          empty={
            <p className="muted">
              {view === 'trash'
                ? 'The trash is empty.'
                : view === 'favorites'
                  ? 'No favorites yet. Open a memory and choose “Favorite”.'
                  : 'No memories yet. Photos you capture in the app will appear here.'}
            </p>
          }
        />
      )}
      {memories.hasNextPage && (
        <p>
          <button
            type="button"
            disabled={memories.isFetchingNextPage}
            onClick={() => void memories.fetchNextPage()}
          >
            {memories.isFetchingNextPage ? 'Loading…' : 'Load more'}
          </button>
        </p>
      )}
    </>
  );
}
