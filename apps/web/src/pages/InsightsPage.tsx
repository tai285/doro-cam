import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api } from '../api/client.ts';
import { usePageTitle } from '../app/use-page-title.ts';
import { BarChart, ErrorNotice } from '../components/parts.tsx';
import { percent } from '../lib/format.ts';

/** Photography statistics (WEB-009, ANL-*) and preset suggestions the user accepts or dismisses (PRE-*). */
export function InsightsPage() {
  usePageTitle('Insights');
  const client = useQueryClient();
  const report = useQuery({ queryKey: ['insights'], queryFn: () => api.insights() });
  const suggestions = useQuery({ queryKey: ['suggestions'], queryFn: api.suggestions });
  const refresh = async () => {
    await client.invalidateQueries({ queryKey: ['suggestions'] });
    await client.invalidateQueries({ queryKey: ['presets'] });
  };
  const accept = useMutation({
    mutationFn: (key: string) => api.acceptSuggestion(key),
    onSuccess: refresh,
  });
  const dismiss = useMutation({
    mutationFn: (key: string) => api.dismissSuggestion(key),
    onSuccess: refresh,
  });

  if (report.isPending) {
    return <p role="status">Crunching your numbers…</p>;
  }
  if (report.isError) {
    return (
      <>
        <h1>Insights</h1>
        <ErrorNotice error={report.error} />
      </>
    );
  }
  const data = report.data;
  return (
    <>
      <h1>Insights</h1>
      {data.total === 0 ? (
        <p className="muted">Take some photos in the app and your habits will show up here.</p>
      ) : (
        <p className="muted">
          Based on {data.total} {data.total === 1 ? 'memory' : 'memories'}. Everything here is
          calculated from your own photos’ settings.
        </p>
      )}

      {data.insights.length > 0 && (
        <section aria-labelledby="findings">
          <h2 id="findings">What we noticed</h2>
          <ul>
            {data.insights.map((insight) => (
              <li key={insight.id}>
                {insight.text}{' '}
                <span className="muted">
                  ({String(insight.basedOn.count)} of {String(insight.basedOn.of)})
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section aria-labelledby="suggested">
        <h2 id="suggested">Suggested presets</h2>
        {suggestions.data?.items.length === 0 || suggestions.data === undefined ? (
          <p className="muted">
            No suggestions yet. When you often shoot with the same combination, we’ll offer it as a
            preset.
          </p>
        ) : (
          <ul className="cards">
            {suggestions.data.items.map((suggestion) => (
              <li key={suggestion.patternKey} className="card">
                <h3>{suggestion.title}</h3>
                <p>{suggestion.explanation}</p>
                <p className="muted">
                  Based on {suggestion.supportingCount} of {suggestion.of} photos (
                  {percent(suggestion.share)}). Nothing changes unless you accept.
                </p>
                <p className="actions">
                  <button
                    type="button"
                    disabled={accept.isPending}
                    onClick={() => {
                      accept.mutate(suggestion.patternKey);
                    }}
                  >
                    Save as preset
                  </button>
                  <button
                    type="button"
                    disabled={dismiss.isPending}
                    onClick={() => {
                      dismiss.mutate(suggestion.patternKey);
                    }}
                  >
                    Not now
                  </button>
                </p>
              </li>
            ))}
          </ul>
        )}
        <ErrorNotice error={accept.error ?? dismiss.error ?? suggestions.error} />
      </section>

      {data.total > 0 && (
        <>
          <h2>Your shooting</h2>
          <div className="charts">
            <BarChart title="Focal length" distribution={data.focalLength} />
            <BarChart title="Lens" distribution={data.lens} />
            <BarChart title="Profile" distribution={data.profile} />
            <BarChart title="Experience" distribution={data.experience} />
            <BarChart title="ISO" distribution={data.iso} />
            <BarChart title="Shutter speed" distribution={data.shutter} />
            <BarChart title="Aperture" distribution={data.aperture} />
            <BarChart title="Time of day" distribution={data.timeOfDay} />
          </div>
          <section aria-labelledby="trend">
            <h2 id="trend">Over time</h2>
            <table>
              <caption className="visually-hidden">Photos per month</caption>
              <thead>
                <tr>
                  <th scope="col">Month</th>
                  <th scope="col">Photos</th>
                </tr>
              </thead>
              <tbody>
                {data.trend.map((point) => (
                  <tr key={point.month}>
                    <th scope="row">{point.month}</th>
                    <td>{point.count}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
        </>
      )}
    </>
  );
}
