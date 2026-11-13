import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { type SyntheticEvent, useState } from 'react';
import { useNavigate } from 'react-router';
import { api } from '../api/client.ts';
import { useMe } from '../auth/RequireAuth.tsx';
import { usePageTitle } from '../app/use-page-title.ts';
import { ErrorNotice, Field, StorageMeter } from '../components/parts.tsx';
import { formatBytes, formatDate } from '../lib/format.ts';

/** Profile, storage, device sessions and account deletion (WEB-005, WEB-006, AUTH-004, PRIV-004). */
export function AccountPage() {
  usePageTitle('Account');
  const me = useMe();
  const client = useQueryClient();
  const navigate = useNavigate();
  const sessions = useQuery({ queryKey: ['sessions'], queryFn: api.sessions });
  const [password, setPassword] = useState('');
  // While an export is being prepared, check again every couple of seconds.
  const exports = useQuery({
    queryKey: ['exports'],
    queryFn: api.exports,
    refetchInterval: (query) =>
      query.state.data?.items.some(
        (item) => item.status === 'pending' || item.status === 'building',
      ) === true
        ? 2000
        : false,
  });
  const requestExport = useMutation({
    mutationFn: () => api.requestExport(),
    onSuccess: () => client.invalidateQueries({ queryKey: ['exports'] }),
  });

  const revoke = useMutation({
    mutationFn: (id: string) => api.revokeSession(id),
    onSuccess: () => client.invalidateQueries({ queryKey: ['sessions'] }),
  });
  const requestDeletion = useMutation({
    mutationFn: () => api.requestDeletion(password),
    onSuccess: async () => {
      setPassword('');
      await client.invalidateQueries({ queryKey: ['me'] });
    },
  });
  const cancelDeletion = useMutation({
    mutationFn: () => api.cancelDeletion(),
    onSuccess: () => client.invalidateQueries({ queryKey: ['me'] }),
  });
  const signOut = useMutation({
    mutationFn: () => api.signOut(),
    onSuccess: () => {
      client.clear();
      void navigate('/sign-in');
    },
  });

  if (me.data === undefined || me.data === null) {
    return <p role="status">Loading…</p>;
  }
  const account = me.data;
  const submitDeletion = (event: SyntheticEvent) => {
    event.preventDefault();
    requestDeletion.mutate();
  };

  return (
    <>
      <h1>Account</h1>
      <p>
        {account.name} · {account.email}
      </p>
      <StorageMeter used={account.storage.usedBytes} quota={account.storage.quotaBytes} />
      <p>
        <button
          type="button"
          disabled={signOut.isPending}
          onClick={() => {
            signOut.mutate();
          }}
        >
          Sign out
        </button>
      </p>

      <section aria-labelledby="devices" className="card">
        <h2 id="devices">Signed-in devices</h2>
        <ErrorNotice error={sessions.error ?? revoke.error} />
        <ul>
          {sessions.data?.items.map((session) => (
            <li key={session.id}>
              {session.userAgent ?? 'Unknown device'} · since {formatDate(session.createdAt)}
              {session.current ? (
                <strong> (this device)</strong>
              ) : (
                <>
                  {' '}
                  <button
                    type="button"
                    onClick={() => {
                      revoke.mutate(session.id);
                    }}
                  >
                    Sign out this device
                  </button>
                </>
              )}
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="export-title" className="card">
        <h2 id="export-title">Your data</h2>
        <p>
          Download everything you’ve captured: your original files plus a metadata file with
          captions, settings and albums.
        </p>
        <button
          type="button"
          disabled={
            requestExport.isPending ||
            exports.data?.items.some(
              (item) => item.status === 'pending' || item.status === 'building',
            ) === true
          }
          onClick={() => {
            requestExport.mutate();
          }}
        >
          Request data export
        </button>
        <ErrorNotice error={exports.error ?? requestExport.error} />
        <ul>
          {exports.data?.items.map((item) => (
            <li key={item.id}>
              {formatDate(item.createdAt)} —{' '}
              {item.status === 'ready' && item.download !== null ? (
                <a href={item.download.url} download={item.download.filename}>
                  Download ({formatBytes(item.bytes ?? 0)})
                </a>
              ) : item.status === 'failed' ? (
                <span role="alert">
                  Failed: {item.failureReason ?? 'unknown error'}. Try again.
                </span>
              ) : item.status === 'ready' ? (
                <span>Expired. Request a new export.</span>
              ) : (
                <span role="status">Preparing your archive…</span>
              )}
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="delete-title" className="card">
        <h2 id="delete-title">Delete account</h2>
        {account.deletionScheduledFor === null ? (
          <form onSubmit={submitDeletion}>
            <p>
              This permanently deletes your account, memories and media after a 7-day grace period.
              You can cancel during that time.
            </p>
            <Field
              id="delete-password"
              label="Confirm your password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={setPassword}
              required
            />
            <ErrorNotice error={requestDeletion.error} />
            <button type="submit" className="danger" disabled={requestDeletion.isPending}>
              Delete my account
            </button>
          </form>
        ) : (
          <>
            <p role="status">
              Your account is scheduled for deletion on{' '}
              <strong>{formatDate(account.deletionScheduledFor)}</strong>.
            </p>
            <button
              type="button"
              disabled={cancelDeletion.isPending}
              onClick={() => {
                cancelDeletion.mutate();
              }}
            >
              Cancel deletion
            </button>
            <ErrorNotice error={cancelDeletion.error} />
          </>
        )}
      </section>
    </>
  );
}
