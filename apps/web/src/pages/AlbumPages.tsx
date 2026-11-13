import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { type SyntheticEvent, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router';
import { api, ApiError } from '../api/client.ts';
import type { Album, AlbumRole } from '../api/types.ts';
import { usePageTitle } from '../app/use-page-title.ts';
import { useMe } from '../auth/RequireAuth.tsx';
import { ErrorNotice, Field, MemoryGrid } from '../components/parts.tsx';
import { formatDate } from '../lib/format.ts';

/** What each role may do (docs/architecture/security.md). The server enforces it; the UI only hides what would be refused. */
export const canEditAlbum = (role: AlbumRole) => role === 'owner' || role === 'editor';
export const canAddMemories = (role: AlbumRole) => role !== 'viewer';
export const canManageMembers = (role: AlbumRole) => role === 'owner';

export function AlbumsPage() {
  usePageTitle('Albums');
  const client = useQueryClient();
  const navigate = useNavigate();
  const albums = useQuery({ queryKey: ['albums'], queryFn: api.albums });
  const [title, setTitle] = useState('');
  const [trip, setTrip] = useState(false);
  const [startsOn, setStartsOn] = useState('');
  const [endsOn, setEndsOn] = useState('');
  const create = useMutation({
    mutationFn: () =>
      api.createAlbum({
        title,
        kind: trip ? 'trip' : 'album',
        ...(trip ? { startsOn, endsOn } : {}),
      }),
    onSuccess: async (album) => {
      await client.invalidateQueries({ queryKey: ['albums'] });
      void navigate(`/albums/${album.id}`);
    },
  });
  const submit = (event: SyntheticEvent) => {
    event.preventDefault();
    create.mutate();
  };

  return (
    <>
      <h1>Albums</h1>
      <p className="muted">
        Share Memories with friends. Everyone keeps their own originals; albums only add access.
      </p>
      <ErrorNotice error={albums.error} />
      {albums.isPending ? (
        <p role="status">Loading albums…</p>
      ) : albums.data?.items.length === 0 ? (
        <p className="muted">You aren’t in any albums yet.</p>
      ) : (
        <ul className="cards" aria-label="Your albums">
          {albums.data?.items.map((album) => (
            <li key={album.id} className="card">
              <h2>
                <Link to={`/albums/${album.id}`}>{album.title}</Link>
              </h2>
              <p className="muted">
                {album.kind === 'trip' && album.startsOn !== null && album.endsOn !== null
                  ? `Trip · ${formatDate(album.startsOn)} – ${formatDate(album.endsOn)} · `
                  : ''}
                {album.itemCount} {album.itemCount === 1 ? 'memory' : 'memories'} ·{' '}
                {album.memberCount} {album.memberCount === 1 ? 'member' : 'members'} · You are{' '}
                {album.role === 'owner' ? 'the owner' : `a ${album.role}`}
              </p>
            </li>
          ))}
        </ul>
      )}

      <form className="card narrow" onSubmit={submit} aria-labelledby="new-album">
        <h2 id="new-album">New album</h2>
        <Field id="album-title" label="Title" value={title} onChange={setTitle} required />
        <div className="field">
          <label>
            <input
              type="checkbox"
              checked={trip}
              onChange={(event) => {
                setTrip(event.target.checked);
              }}
            />{' '}
            This is a trip (has dates)
          </label>
        </div>
        {trip && (
          <>
            <Field
              id="album-start"
              label="Starts on"
              type="date"
              value={startsOn}
              onChange={setStartsOn}
              required
            />
            <Field
              id="album-end"
              label="Ends on"
              type="date"
              value={endsOn}
              onChange={setEndsOn}
              required
            />
          </>
        )}
        <ErrorNotice error={create.error} />
        <button type="submit" disabled={create.isPending}>
          Create album
        </button>
      </form>
    </>
  );
}

function AlbumSettings({ album }: { album: Album }) {
  const client = useQueryClient();
  const patch = useMutation({
    mutationFn: (body: Parameters<typeof api.patchAlbum>[1]) => api.patchAlbum(album.id, body),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ['album', album.id] });
      await client.invalidateQueries({ queryKey: ['albums'] });
    },
  });
  const toggle = (
    label: string,
    checked: boolean,
    key: 'allowOriginalDownload' | 'shareLocation' | 'autoAddDuringTrip',
  ) => (
    <label className="switch">
      <input
        type="checkbox"
        checked={checked}
        disabled={patch.isPending}
        onChange={(event) => {
          patch.mutate({ [key]: event.target.checked });
        }}
      />{' '}
      {label}
    </label>
  );
  return (
    <section aria-labelledby="settings-title" className="card">
      <h2 id="settings-title">Settings</h2>
      {toggle(
        'Members may download originals',
        album.allowOriginalDownload,
        'allowOriginalDownload',
      )}
      {toggle(
        'Show location to members (a Memory also needs its own sharing switched on)',
        album.shareLocation,
        'shareLocation',
      )}
      {album.kind === 'trip' &&
        toggle(
          'Suggest my photos taken during the trip',
          album.autoAddDuringTrip,
          'autoAddDuringTrip',
        )}
      <ErrorNotice error={patch.error} />
    </section>
  );
}

export function AlbumPage() {
  const { id = '' } = useParams();
  const client = useQueryClient();
  const navigate = useNavigate();
  const self = useMe().data;
  const detail = useQuery({ queryKey: ['album', id], queryFn: () => api.album(id) });
  const memories = useQuery({
    queryKey: ['album-memories', id],
    queryFn: () => api.albumMemories(id),
  });
  const proposals = useQuery({
    queryKey: ['trip-proposals', id],
    queryFn: () => api.tripProposals(id),
    enabled: detail.data?.album.kind === 'trip' && detail.data.album.autoAddDuringTrip,
  });
  const library = useQuery({
    queryKey: ['memories', 'picker'],
    queryFn: () => api.memories({ limit: 60 }),
    enabled: detail.data !== undefined && canAddMemories(detail.data.album.role),
  });
  usePageTitle(detail.data?.album.title ?? 'Album');
  const [inviteRole, setInviteRole] = useState<'editor' | 'contributor' | 'viewer'>('contributor');
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteLink, setInviteLink] = useState<string | null>(null);
  const [picked, setPicked] = useState<string[]>([]);

  const refresh = async () => {
    await client.invalidateQueries({ queryKey: ['album', id] });
    await client.invalidateQueries({ queryKey: ['album-memories', id] });
    await client.invalidateQueries({ queryKey: ['trip-proposals', id] });
    await client.invalidateQueries({ queryKey: ['albums'] });
  };
  const add = useMutation({
    mutationFn: (ids: string[]) => api.addToAlbum(id, ids),
    onSuccess: async () => {
      setPicked([]);
      await refresh();
    },
  });
  const remove = useMutation({
    mutationFn: (memoryId: string) => api.removeFromAlbum(id, memoryId),
    onSuccess: refresh,
  });
  const invite = useMutation({
    mutationFn: () =>
      api.createInvite(id, {
        role: inviteRole,
        ...(inviteEmail.trim() === '' ? {} : { email: inviteEmail.trim() }),
      }),
    onSuccess: (result) => {
      setInviteLink(`${window.location.origin}/invites/${result.token}`);
      setInviteEmail('');
    },
  });
  const changeRole = useMutation({
    mutationFn: (input: { userId: string; role: 'editor' | 'contributor' | 'viewer' }) =>
      api.changeMemberRole(id, input.userId, input.role),
    onSuccess: refresh,
  });
  const removeMember = useMutation({
    mutationFn: (userId: string) => api.removeMember(id, userId),
    onSuccess: refresh,
  });
  const leave = useMutation({
    mutationFn: (userId: string) => api.removeMember(id, userId),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ['albums'] });
      void navigate('/albums');
    },
  });
  const deleteAlbum = useMutation({
    mutationFn: () => api.deleteAlbum(id),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ['albums'] });
      void navigate('/albums');
    },
  });

  if (detail.isPending) {
    return <p role="status">Loading…</p>;
  }
  if (detail.isError) {
    const missing = detail.error instanceof ApiError && detail.error.status === 404;
    return (
      <>
        <h1>{missing ? 'Album not found' : 'We couldn’t load this album'}</h1>
        <p>
          <Link to="/albums">Back to albums</Link>
        </p>
      </>
    );
  }
  const { album, members } = detail.data;
  const inAlbum = new Set(memories.data?.items.map((memory) => memory.id) ?? []);
  const candidates = (library.data?.items ?? []).filter((memory) => !inAlbum.has(memory.id));
  const suggested = proposals.data?.memoryIds ?? [];

  return (
    <>
      <p>
        <Link to="/albums">← All albums</Link>
      </p>
      <h1>{album.title}</h1>
      {album.description !== null && <p>{album.description}</p>}
      <p className="muted">
        {album.kind === 'trip' && album.startsOn !== null && album.endsOn !== null
          ? `${formatDate(album.startsOn)} – ${formatDate(album.endsOn)} · `
          : ''}
        You are {album.role === 'owner' ? 'the owner' : `a ${album.role}`}.
      </p>

      <h2>Memories</h2>
      <MemoryGrid
        memories={memories.data?.items ?? []}
        empty={<p className="muted">No memories in this album yet.</p>}
      />

      {canAddMemories(album.role) && (
        <section className="card" aria-labelledby="add-title">
          <h2 id="add-title">Add your memories</h2>
          {suggested.length > 0 && (
            <p>
              {suggested.length} of your photos were taken during this trip.{' '}
              <button
                type="button"
                disabled={add.isPending}
                onClick={() => {
                  add.mutate(suggested);
                }}
              >
                Add all {suggested.length}
              </button>
            </p>
          )}
          {candidates.length === 0 ? (
            <p className="muted">Everything in your library is already here.</p>
          ) : (
            <>
              <ul className="picker" aria-label="Your memories to add">
                {candidates.slice(0, 24).map((memory) => (
                  <li key={memory.id}>
                    <label>
                      <input
                        type="checkbox"
                        checked={picked.includes(memory.id)}
                        onChange={(event) => {
                          setPicked((current) =>
                            event.target.checked
                              ? [...current, memory.id]
                              : current.filter((x) => x !== memory.id),
                          );
                        }}
                      />{' '}
                      {memory.caption ?? new Date(memory.capturedAt).toLocaleDateString('en-GB')}
                    </label>
                  </li>
                ))}
              </ul>
              <button
                type="button"
                disabled={picked.length === 0 || add.isPending}
                onClick={() => {
                  add.mutate(picked);
                }}
              >
                Add selected ({picked.length})
              </button>
            </>
          )}
        </section>
      )}
      {memories.data?.items.some((memory) => canEditAlbum(album.role) || memory.isOwner) ===
        true && (
        <section aria-labelledby="remove-title">
          <h2 id="remove-title">Remove from album</h2>
          <ul className="picker">
            {memories.data.items
              .filter((memory) => canEditAlbum(album.role) || memory.isOwner)
              .map((memory) => (
                <li key={memory.id}>
                  {memory.caption ?? new Date(memory.capturedAt).toLocaleDateString('en-GB')}{' '}
                  <button
                    type="button"
                    onClick={() => {
                      remove.mutate(memory.id);
                    }}
                  >
                    Remove
                  </button>
                </li>
              ))}
          </ul>
        </section>
      )}

      <section aria-labelledby="members-title" className="card">
        <h2 id="members-title">Members</h2>
        <ul>
          {members.map((member) => (
            <li key={member.userId}>
              {member.name} — {member.role}
              {canManageMembers(album.role) && member.role !== 'owner' && (
                <>
                  {' '}
                  <label className="visually-hidden" htmlFor={`role-${member.userId}`}>
                    Role for {member.name}
                  </label>
                  <select
                    id={`role-${member.userId}`}
                    value={member.role}
                    onChange={(event) => {
                      changeRole.mutate({
                        userId: member.userId,
                        role: event.target.value as 'editor' | 'contributor' | 'viewer',
                      });
                    }}
                  >
                    <option value="editor">Editor</option>
                    <option value="contributor">Contributor</option>
                    <option value="viewer">Viewer</option>
                  </select>{' '}
                  <button
                    type="button"
                    onClick={() => {
                      removeMember.mutate(member.userId);
                    }}
                  >
                    Remove {member.name}
                  </button>
                </>
              )}
            </li>
          ))}
        </ul>
        {album.role !== 'owner' && (
          <button
            type="button"
            className="danger"
            onClick={() => {
              if (
                self !== undefined &&
                self !== null &&
                window.confirm('Leave this album? Memories you added stay unless you remove them.')
              ) {
                leave.mutate(self.id);
              }
            }}
          >
            Leave album
          </button>
        )}
        <ErrorNotice error={changeRole.error ?? removeMember.error ?? leave.error} />
      </section>

      {canManageMembers(album.role) && (
        <section aria-labelledby="invite-title" className="card narrow">
          <h2 id="invite-title">Invite someone</h2>
          <div className="field">
            <label htmlFor="invite-role">Role</label>
            <select
              id="invite-role"
              value={inviteRole}
              onChange={(event) => {
                setInviteRole(event.target.value as 'editor' | 'contributor' | 'viewer');
              }}
            >
              <option value="contributor">Contributor (can add their own memories)</option>
              <option value="editor">Editor (can also edit the album)</option>
              <option value="viewer">Viewer (view only)</option>
            </select>
          </div>
          <Field
            id="invite-email"
            label="Email (optional)"
            type="email"
            value={inviteEmail}
            onChange={setInviteEmail}
            hint="We’ll email them the link. Or copy it below."
          />
          <button
            type="button"
            disabled={invite.isPending}
            onClick={() => {
              invite.mutate();
            }}
          >
            Create invite link
          </button>
          {inviteLink !== null && (
            <p role="status">
              Share this link (it is shown once): <code>{inviteLink}</code>
            </p>
          )}
          <ErrorNotice error={invite.error} />
        </section>
      )}

      {canEditAlbum(album.role) && <AlbumSettings album={album} />}

      {canManageMembers(album.role) && (
        <p>
          <button
            type="button"
            className="danger"
            onClick={() => {
              if (window.confirm('Delete this album? Memories are not deleted.')) {
                deleteAlbum.mutate();
              }
            }}
          >
            Delete album
          </button>
        </p>
      )}
      <ErrorNotice error={add.error ?? remove.error ?? deleteAlbum.error ?? detail.error} />
    </>
  );
}

export function InviteAcceptPage() {
  usePageTitle('Join album');
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const accept = useMutation({
    mutationFn: () => api.acceptInvite(token),
    onSuccess: (result) => {
      void navigate(`/albums/${result.albumId}`, { replace: true });
    },
  });
  const message =
    accept.error instanceof ApiError
      ? accept.error.code === 'invite.expired'
        ? 'This invite has expired. Ask the owner for a new one.'
        : accept.error.code === 'invite.revoked'
          ? 'This invite was cancelled.'
          : accept.error.code === 'invite.exhausted'
            ? 'This invite has already been used.'
            : accept.error.status === 404
              ? 'We couldn’t find this invite.'
              : accept.error.message
      : null;
  return (
    <section className="card narrow">
      <h1>Join an album</h1>
      <p>You’ve been invited to share an album on Doro Cam.</p>
      {message !== null && (
        <p role="alert" className="notice error">
          {message}
        </p>
      )}
      <button
        type="button"
        disabled={accept.isPending}
        onClick={() => {
          accept.mutate();
        }}
      >
        {accept.isPending ? 'Joining…' : 'Accept invite'}
      </button>
    </section>
  );
}
