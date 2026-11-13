import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { type SyntheticEvent, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router';
import { api, ApiError, mediaHref } from '../api/client.ts';
import type { Memory } from '../api/types.ts';
import { usePageTitle } from '../app/use-page-title.ts';
import { ErrorNotice } from '../components/parts.tsx';
import { formatBytes, formatCaptured, formatShutter, memoryLabel } from '../lib/format.ts';

const FLASH_LABELS: Record<string, string> = { off: 'Off', auto: 'Auto', on: 'On', torch: 'Torch' };

/** Rows of capture metadata worth showing, from the settings the device actually applied (CAM-050). */
export function captureRows(memory: Memory): Array<[string, string]> {
  const capture = memory.capture;
  const rows: Array<[string, string]> = [];
  const text = (key: string): string | undefined => {
    const value = capture[key];
    return typeof value === 'string' || typeof value === 'number' ? String(value) : undefined;
  };
  const num = (key: string): number | undefined => {
    const value = capture[key];
    return typeof value === 'number' ? value : undefined;
  };
  const camera = [text('deviceMake'), text('deviceModel')]
    .filter((part): part is string => part !== undefined)
    .join(' ');
  if (camera !== '') rows.push(['Camera', camera]);
  if (text('lensKind') !== undefined) rows.push(['Lens', text('lensKind') as string]);
  const focal = num('focalLength35mmEq');
  if (focal !== undefined) rows.push(['Focal length (35 mm equivalent)', `${String(focal)} mm`]);
  const aperture = num('aperture');
  if (aperture !== undefined) rows.push(['Aperture', `f/${String(aperture)}`]);
  if (num('exposureTimeNsApplied') !== undefined)
    rows.push(['Shutter', formatShutter(num('exposureTimeNsApplied') as number)]);
  if (num('isoApplied') !== undefined) rows.push(['ISO', String(num('isoApplied'))]);
  const bias = num('exposureBiasEv');
  if (bias !== undefined)
    rows.push(['Exposure compensation', `${bias > 0 ? '+' : ''}${String(bias)} EV`]);
  const flash = text('flash');
  if (flash !== undefined) rows.push(['Flash', FLASH_LABELS[flash] ?? flash]);
  const width = num('widthPx');
  const height = num('heightPx');
  if (width !== undefined && height !== undefined)
    rows.push(['Size', `${String(width)} × ${String(height)}`]);
  rows.push(['Experience', memory.experienceId]);
  if (memory.profile !== null) rows.push(['Profile', memory.profile.id]);
  if (memory.scenario !== null) rows.push(['Scenario', memory.scenario]);
  if (memory.aspectRatio !== null) rows.push(['Aspect ratio', memory.aspectRatio]);
  return rows;
}

/** A Motion Memory clip. It is the user's own recording with ambient sound and no speech track to caption. */
function MotionVideo(props: { src: string; poster: string | undefined; onEnded: () => void }) {
  return (
    // eslint-disable-next-line jsx-a11y/media-has-caption
    <video
      src={props.src}
      poster={props.poster}
      controls
      autoPlay
      playsInline
      aria-label="Motion playback"
      onEnded={props.onEnded}
    />
  );
}

/** Photo and motion memory detail with playback, metadata, edits, trash and original download (WEB-003, WEB-004, MOT-004, MOT-006). */
export function MemoryPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const client = useQueryClient();
  const memoryQuery = useQuery({ queryKey: ['memory', id], queryFn: () => api.memory(id) });
  const memory = memoryQuery.data;
  usePageTitle(memory === undefined ? 'Memory' : memoryLabel(memory));

  const [caption, setCaption] = useState<string | null>(null);
  const [playing, setPlaying] = useState(false);

  const refresh = async () => {
    await client.invalidateQueries({ queryKey: ['memory', id] });
    await client.invalidateQueries({ queryKey: ['memories'] });
    await client.invalidateQueries({ queryKey: ['me'] });
  };
  const patch = useMutation({
    mutationFn: (body: Parameters<typeof api.patchMemory>[1]) => api.patchMemory(id, body),
    onSuccess: refresh,
  });
  const trash = useMutation({
    mutationFn: () => api.trashMemory(id),
    onSuccess: async () => {
      await refresh();
      void navigate('/');
    },
  });
  const restore = useMutation({ mutationFn: () => api.restoreMemory(id), onSuccess: refresh });
  const purge = useMutation({
    mutationFn: () => api.deleteMemory(id),
    onSuccess: async () => {
      await refresh();
      void navigate('/?view=trash');
    },
  });
  const download = useMutation({
    mutationFn: async (assetId: string) => {
      const link = await api.download(id, assetId);
      const anchor = document.createElement('a');
      anchor.href = mediaHref(link.url);
      anchor.download = link.filename;
      anchor.rel = 'noopener';
      document.body.append(anchor);
      anchor.click();
      anchor.remove();
    },
  });

  const motionAsset = memory?.assets.find(
    (asset) =>
      (asset.role === 'motion_web' || asset.role === 'motion_clip') &&
      (asset.status === 'verified' || asset.status === 'ready'),
  );
  const motionAssetId =
    memory?.assets.find(
      (asset) =>
        asset.role === 'motion_web' && (asset.status === 'verified' || asset.status === 'ready'),
    )?.id ?? motionAsset?.id;
  const motion = useQuery({
    queryKey: ['motion-url', id, motionAssetId],
    queryFn: () => api.download(id, motionAssetId as string),
    enabled: memory?.kind === 'motion' && motionAssetId !== undefined,
    staleTime: 5 * 60_000,
  });

  if (memoryQuery.isPending) {
    return <p role="status">Loading…</p>;
  }
  if (memoryQuery.isError || memory === undefined) {
    const notFound = memoryQuery.error instanceof ApiError && memoryQuery.error.status === 404;
    return (
      <>
        <h1>{notFound ? 'Memory not found' : 'We couldn’t load this memory'}</h1>
        <p>
          {notFound
            ? 'It may have been deleted, or you may not have access to it.'
            : memoryQuery.error.message}
        </p>
        <p>
          <Link to="/">Back to your library</Link>
        </p>
      </>
    );
  }

  const trashed = memory.deletedAt !== null;
  const original = memory.assets.find(
    (asset) => asset.role === 'photo_original' || asset.role === 'video_original',
  );
  const shownCaption = caption ?? memory.caption ?? '';
  const save = (event: SyntheticEvent) => {
    event.preventDefault();
    patch.mutate(
      { caption: shownCaption.trim() === '' ? null : shownCaption.trim() },
      {
        onSuccess: () => {
          setCaption(null);
        },
      },
    );
  };

  return (
    <>
      <p>
        <Link to="/">← Back to library</Link>
      </p>
      <h1>{memoryLabel(memory)}</h1>
      <p className="muted">
        Shot {formatCaptured(memory.capturedAt, memory.capturedTz)} ({memory.capturedTz})
        {memory.kind === 'motion' && ' · Motion Memory'}
        {trashed && ' · In the trash'}
      </p>

      <div className="detail">
        <div className="media">
          {playing && motion.data !== undefined ? (
            <MotionVideo
              src={mediaHref(motion.data.url)}
              poster={memory.display === null ? undefined : mediaHref(memory.display.url)}
              onEnded={() => {
                setPlaying(false);
              }}
            />
          ) : memory.display === null ? (
            <p className="empty muted">This photo is still uploading.</p>
          ) : (
            <img src={mediaHref(memory.display.url)} alt={memoryLabel(memory)} />
          )}
          {memory.kind === 'motion' && motion.data !== undefined && (
            <button
              type="button"
              onClick={() => {
                setPlaying((current) => !current);
              }}
            >
              {playing ? 'Back to photo' : 'Play motion'}
            </button>
          )}
        </div>

        <div className="side">
          <h2>Details</h2>
          <dl className="meta">
            {captureRows(memory).map(([label, value]) => (
              <div key={label}>
                <dt>{label}</dt>
                <dd>{value}</dd>
              </div>
            ))}
            {memory.location !== null && (
              <div>
                <dt>Location</dt>
                <dd>
                  {memory.location.lat.toFixed(4)}, {memory.location.lon.toFixed(4)}
                </dd>
              </div>
            )}
          </dl>

          {memory.isOwner && !trashed && (
            <>
              <form onSubmit={save} className="stack">
                <label htmlFor="caption">Caption</label>
                <textarea
                  id="caption"
                  rows={3}
                  maxLength={2000}
                  value={shownCaption}
                  onChange={(event) => {
                    setCaption(event.target.value);
                  }}
                />
                <button type="submit" disabled={patch.isPending}>
                  Save caption
                </button>
              </form>
              <p className="actions">
                <button
                  type="button"
                  aria-pressed={memory.favorite}
                  onClick={() => {
                    patch.mutate({ favorite: !memory.favorite });
                  }}
                >
                  {memory.favorite ? '★ Favorite' : '☆ Favorite'}
                </button>
                {memory.location !== null && (
                  <button
                    type="button"
                    onClick={() => {
                      patch.mutate({ removeLocation: true });
                    }}
                  >
                    Remove location
                  </button>
                )}
              </p>
            </>
          )}

          {original !== undefined &&
            (original.status === 'verified' || original.status === 'ready') && (
              <p>
                <button
                  type="button"
                  disabled={download.isPending}
                  onClick={() => {
                    download.mutate(original.id);
                  }}
                >
                  Download original ({formatBytes(original.bytes)})
                </button>
              </p>
            )}

          {memory.isOwner && (
            <p className="actions">
              {trashed ? (
                <>
                  <button
                    type="button"
                    onClick={() => {
                      restore.mutate();
                    }}
                  >
                    Restore
                  </button>
                  <button
                    type="button"
                    className="danger"
                    onClick={() => {
                      if (
                        window.confirm('Delete this memory permanently? This cannot be undone.')
                      ) {
                        purge.mutate();
                      }
                    }}
                  >
                    Delete permanently
                  </button>
                </>
              ) : (
                <button
                  type="button"
                  className="danger"
                  onClick={() => {
                    trash.mutate();
                  }}
                >
                  Move to trash
                </button>
              )}
            </p>
          )}
          <ErrorNotice
            error={
              patch.error ??
              trash.error ??
              restore.error ??
              purge.error ??
              download.error ??
              motion.error
            }
          />
        </div>
      </div>
    </>
  );
}
