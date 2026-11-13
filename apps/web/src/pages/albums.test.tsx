import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { canAddMemories, canEditAlbum, canManageMembers } from './AlbumPages.tsx';
import { installFakeApi, makeAlbum, makeMemory } from '../test/fake-api.ts';
import { renderApp } from '../test/render.tsx';

const owner = {
  userId: 'u-1',
  name: 'Dorothy',
  role: 'owner' as const,
  joinedAt: '2026-11-01T00:00:00.000Z',
};
const friend = {
  userId: 'u-2',
  name: 'Friend',
  role: 'viewer' as const,
  joinedAt: '2026-11-02T00:00:00.000Z',
};

describe('role helpers', () => {
  it('[SHR-003] mirror the server’s role matrix', () => {
    expect(
      ['owner', 'editor', 'contributor', 'viewer'].map((r) => canEditAlbum(r as 'owner')),
    ).toEqual([true, true, false, false]);
    expect(
      ['owner', 'editor', 'contributor', 'viewer'].map((r) => canAddMemories(r as 'owner')),
    ).toEqual([true, true, true, false]);
    expect(
      ['owner', 'editor', 'contributor', 'viewer'].map((r) => canManageMembers(r as 'owner')),
    ).toEqual([true, false, false, false]);
  });
});

describe('albums list', () => {
  it('[SHR-001] lists albums with counts and the caller’s role', async () => {
    installFakeApi({
      albums: [
        {
          album: makeAlbum({
            id: 'a1',
            title: 'Japan Trip',
            kind: 'trip',
            startsOn: '2027-04-01',
            endsOn: '2027-04-10',
            itemCount: 12,
            memberCount: 3,
          }),
          members: [owner],
          memoryIds: [],
        },
        {
          album: makeAlbum({
            id: 'a2',
            title: 'Family',
            role: 'contributor',
            itemCount: 1,
            memberCount: 1,
          }),
          members: [owner],
          memoryIds: [],
        },
      ],
    });
    renderApp('/albums');
    const list = await screen.findByRole('list', { name: 'Your albums' });
    expect(within(list).getByRole('link', { name: 'Japan Trip' })).toHaveAttribute(
      'href',
      '/albums/a1',
    );
    expect(
      within(list).getByText(
        /Trip · 1 Apr 2027 – 10 Apr 2027 · 12 memories · 3 members · You are the owner/,
      ),
    ).toBeInTheDocument();
    expect(
      within(list).getByText(/1 memory · 1 member · You are a contributor/),
    ).toBeInTheDocument();
  });

  it('explains when there are no albums', async () => {
    installFakeApi();
    renderApp('/albums');
    expect(await screen.findByText('You aren’t in any albums yet.')).toBeInTheDocument();
  });

  it('[SHR-001] creates an album and opens it', async () => {
    const api = installFakeApi();
    const user = userEvent.setup();
    const { router } = renderApp('/albums');
    await user.type(await screen.findByLabelText('Title'), 'Summer');
    await user.click(screen.getByRole('button', { name: 'Create album' }));
    await waitFor(() => {
      expect(router.state.location.pathname).toMatch(/^\/albums\/a0000000/);
    });
    expect(api.calls('POST', '/v1/albums')[0]?.body).toEqual({ title: 'Summer', kind: 'album' });
  });

  it('[SHR-002] a trip asks for dates', async () => {
    const api = installFakeApi();
    const user = userEvent.setup();
    renderApp('/albums');
    expect(screen.queryByLabelText('Starts on')).not.toBeInTheDocument();
    await user.click(await screen.findByLabelText(/This is a trip/));
    await user.type(screen.getByLabelText('Title'), 'Kyoto');
    await user.type(screen.getByLabelText('Starts on'), '2027-04-01');
    await user.type(screen.getByLabelText('Ends on'), '2027-04-09');
    await user.click(screen.getByRole('button', { name: 'Create album' }));
    await waitFor(() => {
      expect(api.calls('POST', '/v1/albums')).toHaveLength(1);
    });
    expect(api.calls('POST', '/v1/albums')[0]?.body).toEqual({
      title: 'Kyoto',
      kind: 'trip',
      startsOn: '2027-04-01',
      endsOn: '2027-04-09',
    });
  });

  it('shows the server’s reason when creating fails', async () => {
    const api = installFakeApi();
    api.state.failures.set('POST /v1/albums', {
      status: 400,
      code: 'album.invalid_dates',
      message: 'The end date is before the start date.',
    });
    const user = userEvent.setup();
    renderApp('/albums');
    await user.type(await screen.findByLabelText('Title'), 'X');
    await user.click(screen.getByRole('button', { name: 'Create album' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'The end date is before the start date.',
    );
  });
});

describe('album detail', () => {
  const seed = (
    role: 'owner' | 'editor' | 'contributor' | 'viewer',
    extra: Partial<ReturnType<typeof makeAlbum>> = {},
    ids: string[] = [],
  ) =>
    installFakeApi({
      memories: [
        makeMemory({ id: 'mine-1', caption: 'Mine one' }),
        makeMemory({ id: 'mine-2', caption: 'Mine two' }),
        makeMemory({ id: 'theirs', caption: 'Theirs', isOwner: false }),
      ],
      albums: [
        {
          album: makeAlbum({ id: 'a1', title: 'Japan Trip', role, ...extra }),
          members: [owner, friend],
          memoryIds: ids,
        },
      ],
    });

  it('[SHR-001] shows the album’s memories and who is in it', async () => {
    seed('owner', {}, ['theirs']);
    renderApp('/albums/a1');
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Japan Trip' }),
    ).toBeInTheDocument();
    expect(await screen.findByRole('img', { name: 'Theirs' })).toBeInTheDocument();
    const members = screen
      .getByRole('heading', { name: 'Members' })
      .closest('section') as HTMLElement;
    expect(within(members).getByText(/Dorothy — owner/)).toBeInTheDocument();
    expect(within(members).getByText(/Friend — viewer/)).toBeInTheDocument();
  });

  it('[SHR-004] a contributor can add their own memories from the library', async () => {
    const api = seed('contributor');
    const user = userEvent.setup();
    renderApp('/albums/a1');
    const picker = await screen.findByRole('list', { name: 'Your memories to add' });
    expect(within(picker).getAllByRole('checkbox')).toHaveLength(3);
    await user.click(within(picker).getByLabelText('Mine one'));
    await user.click(screen.getByRole('button', { name: 'Add selected (1)' }));
    await waitFor(() => {
      expect(api.calls('POST', '/v1/albums/a1/items')[0]?.body).toEqual({ memoryIds: ['mine-1'] });
    });
    expect(
      await screen
        .findByText('Everything in your library is already here.', {}, { timeout: 100 })
        .catch(() => null),
    ).toBeNull();
  });

  it('[SHR-003] a viewer can only look: no add, invite, settings or delete controls, but can leave', async () => {
    seed('viewer');
    renderApp('/albums/a1');
    await screen.findByRole('heading', { level: 1, name: 'Japan Trip' });
    expect(screen.queryByRole('heading', { name: 'Add your memories' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Invite someone' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Settings' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Delete album' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Leave album' })).toBeInTheDocument();
  });

  it('[SHR-003] an editor can change settings but not invite or delete', async () => {
    seed('editor');
    renderApp('/albums/a1');
    await screen.findByRole('heading', { level: 1, name: 'Japan Trip' });
    expect(screen.getByRole('heading', { name: 'Settings' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Invite someone' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Delete album' })).not.toBeInTheDocument();
  });

  it('[SHR-005][SHR-006] the owner toggles download and location sharing', async () => {
    const api = seed('owner');
    const user = userEvent.setup();
    renderApp('/albums/a1');
    await user.click(await screen.findByLabelText('Members may download originals'));
    await waitFor(() => {
      expect(api.calls('PATCH', '/v1/albums/a1')[0]?.body).toEqual({
        allowOriginalDownload: false,
      });
    });
    await user.click(screen.getByLabelText(/Show location to members/));
    await waitFor(() => {
      expect(api.calls('PATCH', '/v1/albums/a1')[1]?.body).toEqual({ shareLocation: true });
    });
  });

  it('[SHR-002] a trip with auto-add offers the proposed photos and adds them on confirmation', async () => {
    const api = seed('owner', {
      kind: 'trip',
      startsOn: '2027-04-01',
      endsOn: '2027-04-09',
      autoAddDuringTrip: true,
    });
    api.state.tripProposals = ['mine-1', 'mine-2'];
    const user = userEvent.setup();
    renderApp('/albums/a1');
    expect(
      await screen.findByText(/2 of your photos were taken during this trip/),
    ).toBeInTheDocument();
    expect(api.calls('POST', '/v1/albums/a1/items')).toHaveLength(0); // never silently
    await user.click(screen.getByRole('button', { name: 'Add all 2' }));
    await waitFor(() => {
      expect(api.calls('POST', '/v1/albums/a1/items')[0]?.body).toEqual({
        memoryIds: ['mine-1', 'mine-2'],
      });
    });
  });

  it('[SHR-003] the owner creates an invite link that is shown once, and can email it', async () => {
    const api = seed('owner');
    const user = userEvent.setup();
    renderApp('/albums/a1');
    await screen.findByRole('heading', { name: 'Invite someone' });
    await user.selectOptions(screen.getByLabelText('Role'), 'viewer');
    await user.type(screen.getByLabelText('Email (optional)'), 'pal@example.test');
    await user.click(screen.getByRole('button', { name: 'Create invite link' }));
    expect(await screen.findByText(/\/invites\/tok-tok-tok/)).toHaveTextContent(
      `${window.location.origin}/invites/tok-tok-tok-tok-tok-tok-tok-tok-tok`,
    );
    expect(api.calls('POST', '/v1/albums/a1/invites')[0]?.body).toEqual({
      role: 'viewer',
      email: 'pal@example.test',
    });
  });

  it('[SHR-003] the owner changes a member’s role and removes members', async () => {
    const api = seed('owner');
    const user = userEvent.setup();
    renderApp('/albums/a1');
    await user.selectOptions(await screen.findByLabelText('Role for Friend'), 'editor');
    await waitFor(() => {
      expect(api.calls('PATCH', '/v1/albums/a1/members/u-2')[0]?.body).toEqual({ role: 'editor' });
    });
    await user.click(screen.getByRole('button', { name: 'Remove Friend' }));
    await waitFor(() => {
      expect(api.calls('DELETE', '/v1/albums/a1/members/u-2')).toHaveLength(1);
    });
  });

  it('[SHR-007] a member leaves after confirming', async () => {
    const api = seed('viewer');
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    const user = userEvent.setup();
    const { router } = renderApp('/albums/a1');
    await user.click(await screen.findByRole('button', { name: 'Leave album' }));
    await waitFor(() => {
      expect(api.calls('DELETE', '/v1/albums/a1/members/u-1')).toHaveLength(1);
    });
    await waitFor(() => {
      expect(router.state.location.pathname).toBe('/albums');
    });
  });

  it('[SHR-001] removes a memory from the album: editors may remove anyone’s, contributors only their own', async () => {
    const api = seed('contributor', {}, ['mine-1', 'theirs']);
    const user = userEvent.setup();
    renderApp('/albums/a1');
    const section = (await screen.findByRole('heading', { name: 'Remove from album' })).closest(
      'section',
    ) as HTMLElement;
    expect(within(section).getAllByRole('button', { name: 'Remove' })).toHaveLength(1); // only "Mine one"
    await user.click(within(section).getByRole('button', { name: 'Remove' }));
    await waitFor(() => {
      expect(api.calls('DELETE', '/v1/albums/a1/items/mine-1')).toHaveLength(1);
    });
  });

  it('[SHR-001] the owner deletes the album after confirming; memories are untouched', async () => {
    const api = seed('owner');
    vi.spyOn(window, 'confirm').mockReturnValueOnce(false).mockReturnValueOnce(true);
    const user = userEvent.setup();
    const { router } = renderApp('/albums/a1');
    await user.click(await screen.findByRole('button', { name: 'Delete album' }));
    expect(api.calls('DELETE', '/v1/albums/a1')).toHaveLength(0);
    await user.click(screen.getByRole('button', { name: 'Delete album' }));
    await waitFor(() => {
      expect(api.calls('DELETE', '/v1/albums/a1')).toHaveLength(1);
    });
    await waitFor(() => {
      expect(router.state.location.pathname).toBe('/albums');
    });
    expect(api.state.memories).toHaveLength(3);
  });

  it('shows “Album not found” for albums the user is not in (the server answers 404)', async () => {
    installFakeApi();
    renderApp('/albums/nope');
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Album not found' }, { timeout: 4000 }),
    ).toBeInTheDocument();
  });
});

describe('accepting an invite', () => {
  it('[SHR-003] joins the album and opens it', async () => {
    installFakeApi({
      albums: [
        {
          album: makeAlbum({ id: 'a1', title: 'Japan Trip', role: 'contributor' }),
          members: [owner],
          memoryIds: [],
        },
      ],
    });
    const user = userEvent.setup();
    const { router } = renderApp('/invites/a-good-token-a-good-token-a-good-token');
    await user.click(await screen.findByRole('button', { name: 'Accept invite' }));
    await waitFor(() => {
      expect(router.state.location.pathname).toBe('/albums/a1');
    });
  });

  it('[SHR-003] explains expired and unknown invites in plain words', async () => {
    installFakeApi();
    const user = userEvent.setup();
    renderApp('/invites/expired-token-expired-token-expired');
    await user.click(await screen.findByRole('button', { name: 'Accept invite' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'This invite has expired. Ask the owner for a new one.',
    );
  });

  it('[SHR-003] says when an invite cannot be found', async () => {
    installFakeApi();
    const user = userEvent.setup();
    renderApp('/invites/unknown-token-unknown-token-unknown');
    await user.click(await screen.findByRole('button', { name: 'Accept invite' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('We couldn’t find this invite.');
  });

  it('[SHR-003] explains revoked and used-up invites', async () => {
    const api = installFakeApi();
    const user = userEvent.setup();
    renderApp('/invites/some-token-some-token-some-token-x');
    api.state.failures.set('POST /v1/invites/accept', { status: 410, code: 'invite.revoked' });
    await user.click(await screen.findByRole('button', { name: 'Accept invite' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('This invite was cancelled.');
    api.state.failures.set('POST /v1/invites/accept', { status: 410, code: 'invite.exhausted' });
    await user.click(screen.getByRole('button', { name: 'Accept invite' }));
    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('This invite has already been used.');
    });
  });
});
