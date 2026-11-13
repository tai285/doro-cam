import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import type { InsightsReport, PresetSuggestion } from '../api/types.ts';
import { emptyInsights, installFakeApi, makeMe, makePreset } from '../test/fake-api.ts';
import { renderApp } from '../test/render.tsx';

const dist = (rows: Array<[string, number]>, total = rows.reduce((sum, [, n]) => sum + n, 0)) => ({
  total,
  buckets: rows.map(([label, count]) => ({ label, count, share: count / total })),
});

const report: InsightsReport = {
  ...emptyInsights,
  total: 10,
  focalLength: dist([
    ['24-35 mm', 8],
    ['51-85 mm', 2],
  ]),
  lens: dist([
    ['wide', 8],
    ['tele', 2],
  ]),
  profile: dist([
    ['natural', 6],
    ['warm-film', 4],
  ]),
  experience: dist([['mirrorless', 10]]),
  iso: dist([
    ['101-400', 9],
    ['401-1600', 1],
  ]),
  shutter: dist([['1/126-1/500', 10]]),
  aperture: dist([['f/1.0-1.9', 10]]),
  timeOfDay: dist([
    ['Midday (11-16)', 7],
    ['Evening (16-22)', 3],
  ]),
  trend: [
    { month: '2026-04', count: 4 },
    { month: '2026-05', count: 6 },
  ],
  insights: [
    {
      id: 'favorite-focal-length',
      text: 'You shoot most at 24-35 mm (80% of your photos).',
      basedOn: { focalLength: '24-35 mm', count: 8, of: 10 },
    },
  ],
};

const suggestion: PresetSuggestion = {
  patternKey: 'a'.repeat(24),
  title: 'mirrorless · natural · street · wide',
  explanation:
    '8 of your 10 photos (80%) were taken with mirrorless, natural, street, wide, usually at ISO 101-400.',
  experienceId: 'mirrorless',
  profileId: 'natural',
  scenario: 'street',
  lensKind: 'wide',
  isoRange: '101-400',
  shutterRange: null,
  supportingCount: 8,
  of: 10,
  share: 0.8,
};

describe('insights', () => {
  it('[WEB-009][ANL-001][ANL-002] shows distributions as bars with a readable table behind each', async () => {
    installFakeApi({ insights: report });
    renderApp('/insights');
    expect(await screen.findByText(/Based on 10 memories/)).toBeInTheDocument();
    const focal = screen
      .getByRole('heading', { name: 'Focal length' })
      .closest('section') as HTMLElement;
    const rows = within(focal).getAllByRole('row').slice(1);
    expect(rows.map((row) => row.textContent)).toEqual(['24-35 mm880%', '51-85 mm220%']);
    for (const title of [
      'Lens',
      'Profile',
      'Experience',
      'ISO',
      'Shutter speed',
      'Aperture',
      'Time of day',
    ]) {
      expect(screen.getByRole('heading', { name: title })).toBeInTheDocument();
    }
  });

  it('[ANL-004] lists photos per month', async () => {
    installFakeApi({ insights: report });
    renderApp('/insights');
    const table = await screen.findByRole('table', { name: 'Photos per month' });
    expect(
      within(table)
        .getAllByRole('row')
        .slice(1)
        .map((r) => r.textContent),
    ).toEqual(['2026-044', '2026-056']);
  });

  it('[ANL-005] shows each plain-language insight with the numbers it is based on', async () => {
    installFakeApi({ insights: report });
    renderApp('/insights');
    const finding = await screen.findByText(/You shoot most at 24-35 mm/);
    expect(finding.closest('li')).toHaveTextContent('(8 of 10)');
  });

  it('[ANL-005] with no photos it invites the user to take some instead of showing empty charts', async () => {
    installFakeApi();
    renderApp('/insights');
    expect(await screen.findByText(/Take some photos in the app/)).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Focal length' })).not.toBeInTheDocument();
  });

  it('[PRE-002] a suggestion explains the pattern and the data behind it', async () => {
    installFakeApi({ insights: report, suggestions: [suggestion] });
    renderApp('/insights');
    expect(await screen.findByText(suggestion.explanation)).toBeInTheDocument();
    expect(
      screen.getByText(/Based on 8 of 10 photos \(80%\)\. Nothing changes unless you accept\./),
    ).toBeInTheDocument();
  });

  it('[PRE-003] accepting saves a preset; dismissing removes the suggestion; neither happens automatically', async () => {
    const api = installFakeApi({
      insights: report,
      suggestions: [
        suggestion,
        {
          ...suggestion,
          patternKey: 'b'.repeat(24),
          title: 'second',
          explanation: 'Another pattern of yours.',
        },
      ],
    });
    const user = userEvent.setup();
    renderApp('/insights');
    await screen.findByText(suggestion.explanation);
    expect(api.calls('POST', /preset-suggestions/)).toHaveLength(0);
    const [first, second] = screen.getAllByRole('listitem').filter((li) => li.querySelector('h3'));
    await user.click(within(first as HTMLElement).getByRole('button', { name: 'Save as preset' }));
    await waitFor(() => {
      expect(
        api.calls('POST', `/v1/insights/preset-suggestions/${'a'.repeat(24)}/accept`),
      ).toHaveLength(1);
    });
    await waitFor(() => {
      expect(screen.queryByText(suggestion.explanation)).not.toBeInTheDocument();
    });
    expect(second).toBeDefined();
    await user.click(await screen.findByRole('button', { name: 'Not now' }));
    await waitFor(() => {
      expect(
        api.calls('POST', `/v1/insights/preset-suggestions/${'b'.repeat(24)}/dismiss`),
      ).toHaveLength(1);
    });
    expect(await screen.findByText(/No suggestions yet/)).toBeInTheDocument();
  });

  it('shows an error when the insights cannot be loaded', async () => {
    const api = installFakeApi();
    api.state.failures.set('GET /v1/insights/summary', {
      status: 500,
      code: 'internal',
      message: 'Something went wrong on our side.',
    });
    renderApp('/insights');
    expect(await screen.findByRole('alert')).toHaveTextContent('Something went wrong on our side.');
  });
});

describe('presets', () => {
  it('[WEB-008] lists presets with their experience, profile, LIVE flag and origin', async () => {
    installFakeApi({
      presets: [
        makePreset({ name: 'Street 35', live: true }),
        makePreset({ name: 'Auto one', source: 'suggested', profile: null }),
      ],
    });
    renderApp('/presets');
    const list = await screen.findByRole('list', { name: 'Your presets' });
    expect(within(list).getByText('mirrorless · warm-film · LIVE')).toBeInTheDocument();
    expect(within(list).getByText('mirrorless · suggested from your habits')).toBeInTheDocument();
  });

  it('[WEB-008] says when there are none', async () => {
    installFakeApi();
    renderApp('/presets');
    expect(await screen.findByText('No presets yet.')).toBeInTheDocument();
  });

  it('[EXP-007] renames a preset, keeping its other settings', async () => {
    const preset = makePreset({ id: 'p1', name: 'Street 35', live: true });
    const api = installFakeApi({ presets: [preset] });
    const user = userEvent.setup();
    renderApp('/presets');
    await user.click(await screen.findByRole('button', { name: 'Rename' }));
    const field = screen.getByLabelText('Preset name');
    await user.clear(field);
    await user.type(field, '  Street 28  ');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => {
      expect(api.calls('PUT', '/v1/presets/p1')).toHaveLength(1);
    });
    expect(api.calls('PUT', '/v1/presets/p1')[0]?.body).toEqual({
      name: 'Street 28',
      experienceId: 'mirrorless',
      intent: { scenario: 'street' },
      profile: { id: 'warm-film', version: 1 },
      live: true,
    });
    expect(await screen.findByRole('heading', { name: 'Street 28' })).toBeInTheDocument();
  });

  it('[EXP-007] cancelling a rename leaves the name unchanged, and an empty name cannot be saved', async () => {
    installFakeApi({ presets: [makePreset({ id: 'p1', name: 'Keep me' })] });
    const user = userEvent.setup();
    renderApp('/presets');
    await user.click(await screen.findByRole('button', { name: 'Rename' }));
    await user.clear(screen.getByLabelText('Preset name'));
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(screen.getByRole('heading', { name: 'Keep me' })).toBeInTheDocument();
  });

  it('[EXP-007] deletes only after confirmation', async () => {
    const api = installFakeApi({ presets: [makePreset({ id: 'p1', name: 'Bye' })] });
    vi.spyOn(window, 'confirm').mockReturnValueOnce(false).mockReturnValueOnce(true);
    const user = userEvent.setup();
    renderApp('/presets');
    await user.click(await screen.findByRole('button', { name: 'Delete' }));
    expect(api.calls('DELETE', '/v1/presets/p1')).toHaveLength(0);
    await user.click(screen.getByRole('button', { name: 'Delete' }));
    await waitFor(() => {
      expect(api.calls('DELETE', '/v1/presets/p1')).toHaveLength(1);
    });
    expect(await screen.findByText('No presets yet.')).toBeInTheDocument();
  });
});

describe('account', () => {
  it('[WEB-005][WEB-006] shows the profile and storage usage', async () => {
    installFakeApi({
      me: makeMe({ storage: { usedBytes: 1024 ** 3, quotaBytes: 10 * 1024 ** 3 } }),
    });
    renderApp('/account');
    expect(await screen.findByText('Dorothy · dorothy@example.test')).toBeInTheDocument();
    expect(screen.getByText('Storage: 1 GB of 10 GB used')).toBeInTheDocument();
  });

  it('[AUTH-004] lists signed-in devices and signs another one out', async () => {
    const api = installFakeApi();
    api.state.sessions.push({
      id: 's-2',
      current: false,
      userAgent: 'Honor X9c app',
      ipAddress: null,
      createdAt: '2026-11-05T00:00:00.000Z',
      expiresAt: '2026-12-01T00:00:00.000Z',
    });
    const user = userEvent.setup();
    renderApp('/account');
    expect(await screen.findByText('(this device)')).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'Sign out this device' })).toHaveLength(1); // not for the current one
    await user.click(screen.getByRole('button', { name: 'Sign out this device' }));
    await waitFor(() => {
      expect(api.calls('DELETE', '/v1/me/sessions/s-2')).toHaveLength(1);
    });
    await waitFor(() => {
      expect(screen.queryByText(/Honor X9c app/)).not.toBeInTheDocument();
    });
  });

  it('shows “Unknown device” when the user agent is missing', async () => {
    const api = installFakeApi();
    api.state.sessions[0] = {
      id: 's-1',
      current: true,
      userAgent: null,
      ipAddress: null,
      createdAt: '2026-11-01T00:00:00.000Z',
      expiresAt: '2026-12-01T00:00:00.000Z',
    };
    renderApp('/account');
    expect(await screen.findByText(/Unknown device/)).toBeInTheDocument();
  });

  it('[WEB-006][PRIV-004] account deletion needs the password and then shows when it will happen', async () => {
    const api = installFakeApi();
    const user = userEvent.setup();
    renderApp('/account');
    await user.type(await screen.findByLabelText('Confirm your password'), 'wrong-password');
    await user.click(screen.getByRole('button', { name: 'Delete my account' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('The password is incorrect.');
    await user.clear(screen.getByLabelText('Confirm your password'));
    await user.type(screen.getByLabelText('Confirm your password'), 'correct-password');
    await user.click(screen.getByRole('button', { name: 'Delete my account' }));
    expect(await screen.findByText(/scheduled for deletion on/)).toHaveTextContent('20 Nov 2026');
    expect(api.calls('POST', '/v1/me/deletion')).toHaveLength(2);
  });

  it('[WEB-006] a scheduled deletion can be cancelled', async () => {
    const api = installFakeApi({
      me: makeMe({
        deletionRequestedAt: '2026-11-13T00:00:00.000Z',
        deletionScheduledFor: '2026-11-20T00:00:00.000Z',
      }),
    });
    const user = userEvent.setup();
    renderApp('/account');
    await user.click(await screen.findByRole('button', { name: 'Cancel deletion' }));
    await waitFor(() => {
      expect(api.calls('DELETE', '/v1/me/deletion')).toHaveLength(1);
    });
    expect(await screen.findByRole('button', { name: 'Delete my account' })).toBeInTheDocument();
  });

  it('[AUTH-001] signing out ends the session and returns to the sign-in page', async () => {
    const api = installFakeApi();
    const user = userEvent.setup();
    const { router } = renderApp('/account');
    await user.click(await screen.findByRole('button', { name: 'Sign out' }));
    await waitFor(() => {
      expect(router.state.location.pathname).toBe('/sign-in');
    });
    expect(api.calls('POST', '/v1/auth/sign-out')).toHaveLength(1);
    expect(api.state.signedIn).toBe(false);
  });
});
