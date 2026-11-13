import type { ReactNode } from 'react';
import { Link } from 'react-router';
import { ApiError, mediaHref } from '../api/client.ts';
import type { Distribution, Memory } from '../api/types.ts';
import { formatBytes, memoryLabel, percent, usedShare } from '../lib/format.ts';

/** A text field with a visible label, optional hint and an error message announced to assistive technology. */
export function Field(props: {
  id: string;
  label: string;
  type?: string;
  value: string;
  onChange: (value: string) => void;
  autoComplete?: string;
  hint?: string;
  required?: boolean;
  minLength?: number;
  error?: string | null;
}) {
  const hintId = `${props.id}-hint`;
  return (
    <div className="field">
      <label htmlFor={props.id}>{props.label}</label>
      <input
        id={props.id}
        name={props.id}
        type={props.type ?? 'text'}
        value={props.value}
        autoComplete={props.autoComplete}
        required={props.required}
        minLength={props.minLength}
        aria-describedby={props.hint === undefined ? undefined : hintId}
        aria-invalid={props.error ? true : undefined}
        onChange={(event) => {
          props.onChange(event.target.value);
        }}
      />
      {props.hint !== undefined && (
        <p id={hintId} className="muted hint">
          {props.hint}
        </p>
      )}
    </div>
  );
}

export function ErrorNotice({ error }: { error: unknown }) {
  if (error === null || error === undefined) {
    return null;
  }
  const message =
    error instanceof ApiError || error instanceof Error ? error.message : 'Something went wrong.';
  return (
    <p role="alert" className="notice error">
      {message}
    </p>
  );
}

export function StorageMeter({ used, quota }: { used: number; quota: number }) {
  const share = usedShare(used, quota);
  return (
    <div className="storage">
      <p id="storage-label">
        Storage: {formatBytes(used)} of {formatBytes(quota)} used
      </p>
      <meter
        aria-labelledby="storage-label"
        min={0}
        max={quota}
        value={Math.min(used, quota)}
        low={quota * 0.8}
        high={quota * 0.9}
      >
        {percent(share)}
      </meter>
    </div>
  );
}

/** Library grid cell. Thumbnails of other people's Memories come through the authorizing content endpoint. */
export function MemoryGrid({ memories, empty }: { memories: Memory[]; empty: ReactNode }) {
  if (memories.length === 0) {
    return <div className="empty">{empty}</div>;
  }
  return (
    <ul className="grid" aria-label="Memories">
      {memories.map((memory) => (
        <li key={memory.id}>
          <Link to={`/memories/${memory.id}`} className="tile">
            {memory.thumbnail === null ? (
              <span
                className="tile-placeholder"
                role="img"
                aria-label={`${memoryLabel(memory)} (still uploading)`}
              >
                Uploading…
              </span>
            ) : (
              <img src={mediaHref(memory.thumbnail.url)} alt={memoryLabel(memory)} loading="lazy" />
            )}
            <span className="tile-badges">
              {memory.kind === 'motion' && <span className="badge">LIVE</span>}
              {memory.favorite && (
                <span className="badge" aria-label="Favorite">
                  ★
                </span>
              )}
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

/** A distribution as bars plus a table, so the numbers are readable by everyone and not only visible as shapes. */
export function BarChart({ title, distribution }: { title: string; distribution: Distribution }) {
  const max = Math.max(1, ...distribution.buckets.map((bucket) => bucket.count));
  return (
    <section className="chart" aria-labelledby={`chart-${title.replace(/\W+/g, '-')}`}>
      <h3 id={`chart-${title.replace(/\W+/g, '-')}`}>{title}</h3>
      {distribution.buckets.length === 0 ? (
        <p className="muted">Not enough data yet.</p>
      ) : (
        <table>
          <caption className="visually-hidden">{title}</caption>
          <thead>
            <tr>
              <th scope="col">Value</th>
              <th scope="col">Photos</th>
              <th scope="col">Share</th>
            </tr>
          </thead>
          <tbody>
            {distribution.buckets.map((bucket) => (
              <tr key={bucket.label}>
                <th scope="row">{bucket.label}</th>
                <td>
                  <span
                    className="bar"
                    aria-hidden="true"
                    style={{ width: `${String((bucket.count / max) * 100)}%` }}
                  />
                  {bucket.count}
                </td>
                <td>{percent(bucket.share)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
