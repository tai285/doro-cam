import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { installFakeApi, makeMe, makeMemory } from '../test/fake-api.ts';
import { renderApp } from '../test/render.tsx';

describe('library', () => {
  it('[WEB-002][LIB-001] shows memories newest first with thumbnails and readable alt text', async () => {
    installFakeApi({
      memories: [
        makeMemory({ id: 'old', capturedAt: '2026-01-01T10:00:00.000Z' }),
        makeMemory({
          id: 'new',
          capturedAt: '2026-06-01T10:00:00.000Z',
          caption: 'Sunset at the pier',
        }),
      ],
    });
    renderApp('/');
    const grid = await screen.findByRole('list', { name: 'Memories' });
    const links = within(grid).getAllByRole('link');
    expect(links.map((link) => link.getAttribute('href'))).toEqual([
      '/memories/new',
      '/memories/old',
    ]);
    expect(within(grid).getByRole('img', { name: 'Sunset at the pier' })).toHaveAttribute(
      'src',
      'https://media.test/new/thumb.jpg',
    );
    expect(within(grid).getByRole('img', { name: /^Photo from 1 Jan 2026/ })).toBeInTheDocument();
  });

  it('[WEB-002] pages through the library with “Load more” until the end', async () => {
    const memories = Array.from({ length: 30 }, (_, i) =>
      makeMemory({
        id: `m${String(i).padStart(2, '0')}`,
        capturedAt: `2026-03-${String(30 - i).padStart(2, '0')}T10:00:00.000Z`,
      }),
    );
    const api = installFakeApi({ memories });
    const user = userEvent.setup();
    renderApp('/');
    await screen.findByRole('list', { name: 'Memories' });
    expect(screen.getAllByRole('link', { name: /Photo from/ })).toHaveLength(24);
    await user.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(screen.getAllByRole('link', { name: /Photo from/ })).toHaveLength(30);
    });
    expect(screen.queryByRole('button', { name: 'Load more' })).not.toBeInTheDocument();
    expect(api.calls('GET', '/v1/memories').map((call) => call.query.get('cursor'))).toEqual([
      null,
      '24',
    ]);
  });

  it('[MOT-004] marks Motion Memories and favorites on their tiles', async () => {
    installFakeApi({ memories: [makeMemory({ id: 'live', kind: 'motion', favorite: true })] });
    renderApp('/');
    const tile = await screen.findByRole('link', { name: /Motion memory from/ });
    expect(within(tile).getByText('LIVE')).toBeInTheDocument();
    expect(within(tile).getByLabelText('Favorite')).toBeInTheDocument();
  });

  it('[LIB-004] shows a placeholder while a thumbnail has not been uploaded yet', async () => {
    installFakeApi({ memories: [makeMemory({ thumbnail: null })] });
    renderApp('/');
    expect(await screen.findByRole('img', { name: /still uploading/ })).toBeInTheDocument();
  });

  it('explains an empty library', async () => {
    installFakeApi();
    renderApp('/');
    expect(await screen.findByText(/No memories yet/)).toBeInTheDocument();
  });

  it('[LIB-003] filters by kind and favorites through the query string', async () => {
    const api = installFakeApi({
      memories: [
        makeMemory({ id: 'p' }),
        makeMemory({ id: 'm', kind: 'motion' }),
        makeMemory({ id: 'f', favorite: true }),
      ],
    });
    const user = userEvent.setup();
    renderApp('/');
    await screen.findByRole('list', { name: 'Memories' });
    await user.click(screen.getByRole('button', { name: 'Motion' }));
    await waitFor(() => {
      expect(screen.getAllByRole('link', { name: /Motion memory/ })).toHaveLength(1);
    });
    await user.click(screen.getByRole('button', { name: 'Favorites' }));
    await waitFor(() => {
      expect(screen.getAllByRole('link', { name: /Photo from/ })).toHaveLength(1);
    });
    expect(api.calls('GET', '/v1/memories').some((c) => c.query.get('kind') === 'motion')).toBe(
      true,
    );
    expect(api.calls('GET', '/v1/memories').some((c) => c.query.get('favorite') === 'true')).toBe(
      true,
    );
    await user.click(screen.getByRole('button', { name: 'Photos' }));
    await waitFor(() => {
      expect(api.calls('GET', '/v1/memories').some((c) => c.query.get('kind') === 'photo')).toBe(
        true,
      );
    });
    await user.click(screen.getByRole('button', { name: 'All' }));
    expect(screen.getByRole('button', { name: 'All' })).toHaveAttribute('aria-pressed', 'true');
  });

  it('[WEB-005] shows storage usage as a meter', async () => {
    installFakeApi({
      me: makeMe({ storage: { usedBytes: 5 * 1024 ** 3, quotaBytes: 10 * 1024 ** 3 } }),
    });
    renderApp('/');
    expect(await screen.findByText('Storage: 5 GB of 10 GB used')).toBeInTheDocument();
    const meter = screen.getByRole('meter', { name: /Storage/ });
    expect(meter).toHaveAttribute('value', String(5 * 1024 ** 3));
    expect(meter).toHaveAttribute('max', String(10 * 1024 ** 3));
  });

  it('[MEM-007] shows trashed memories and empties the trash after confirmation', async () => {
    const api = installFakeApi({
      memories: [
        makeMemory({ id: 't1', deletedAt: '2026-11-10T00:00:00.000Z' }),
        makeMemory({ id: 'k1' }),
      ],
    });
    const confirm = vi
      .spyOn(window, 'confirm')
      .mockReturnValueOnce(false)
      .mockReturnValueOnce(true);
    const user = userEvent.setup();
    renderApp('/?view=trash');
    expect(await screen.findByText(/deleted permanently after 30 days/)).toBeInTheDocument();
    expect(await screen.findAllByRole('link', { name: /Photo from/ })).toHaveLength(1);
    await user.click(await screen.findByRole('button', { name: 'Empty trash' }));
    expect(api.calls('POST', '/v1/memories/trash/empty')).toHaveLength(0); // declined
    await user.click(screen.getByRole('button', { name: 'Empty trash' }));
    await waitFor(() => {
      expect(api.calls('POST', '/v1/memories/trash/empty')).toHaveLength(1);
    });
    expect(confirm).toHaveBeenCalledTimes(2);
    expect(await screen.findByText('The trash is empty.')).toBeInTheDocument();
  });

  it('shows an error message when the library cannot be loaded', async () => {
    const api = installFakeApi();
    api.state.failures.set('GET /v1/memories', {
      status: 500,
      code: 'internal',
      message: 'Something went wrong on our side.',
    });
    renderApp('/');
    expect(await screen.findByRole('alert')).toHaveTextContent('Something went wrong on our side.');
  });

  it('shows empty-state text for favorites', async () => {
    installFakeApi();
    renderApp('/?view=favorites');
    expect(await screen.findByText(/No favorites yet/)).toBeInTheDocument();
  });
});
