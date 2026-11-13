import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../api/client.ts';
import type { Preset } from '../api/types.ts';
import { usePageTitle } from '../app/use-page-title.ts';
import { ErrorNotice, Field } from '../components/parts.tsx';

function PresetRow({ preset }: { preset: Preset }) {
  const client = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(preset.name);
  const refresh = () => client.invalidateQueries({ queryKey: ['presets'] });
  const rename = useMutation({
    mutationFn: () =>
      api.savePreset(preset.id, {
        name: name.trim(),
        experienceId: preset.experienceId,
        intent: preset.intent,
        profile: preset.profile,
        live: preset.live,
      }),
    onSuccess: async () => {
      setEditing(false);
      await refresh();
    },
  });
  const remove = useMutation({ mutationFn: () => api.deletePreset(preset.id), onSuccess: refresh });
  return (
    <li className="card">
      {editing ? (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            rename.mutate();
          }}
        >
          <Field
            id={`name-${preset.id}`}
            label="Preset name"
            value={name}
            onChange={setName}
            required
          />
          <button type="submit" disabled={rename.isPending || name.trim() === ''}>
            Save
          </button>{' '}
          <button
            type="button"
            onClick={() => {
              setEditing(false);
              setName(preset.name);
            }}
          >
            Cancel
          </button>
        </form>
      ) : (
        <>
          <h2>{preset.name}</h2>
          <p className="muted">
            {preset.experienceId}
            {preset.profile !== null && ` · ${preset.profile.id}`}
            {preset.live && ' · LIVE'}
            {preset.source === 'suggested' && ' · suggested from your habits'}
          </p>
          <p className="actions">
            <button
              type="button"
              onClick={() => {
                setEditing(true);
              }}
            >
              Rename
            </button>
            <button
              type="button"
              className="danger"
              onClick={() => {
                if (window.confirm(`Delete the preset “${preset.name}”?`)) {
                  remove.mutate();
                }
              }}
            >
              Delete
            </button>
          </p>
        </>
      )}
      <ErrorNotice error={rename.error ?? remove.error} />
    </li>
  );
}

/** Preset management (WEB-008, EXP-007). Presets sync with the app through the change feed. */
export function PresetsPage() {
  usePageTitle('Presets');
  const presets = useQuery({ queryKey: ['presets'], queryFn: api.presets });
  return (
    <>
      <h1>Presets</h1>
      <p className="muted">
        Presets are created in the app, or suggested from your habits on the Insights page. Rename
        or remove them here.
      </p>
      <ErrorNotice error={presets.error} />
      {presets.isPending ? (
        <p role="status">Loading presets…</p>
      ) : presets.data?.items.length === 0 ? (
        <p className="muted">No presets yet.</p>
      ) : (
        <ul className="cards" aria-label="Your presets">
          {presets.data?.items.map((preset) => (
            <PresetRow key={preset.id} preset={preset} />
          ))}
        </ul>
      )}
    </>
  );
}
