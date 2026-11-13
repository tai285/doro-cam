import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import type { DataExport } from '../api/types.ts';
import { installFakeApi, makeMemory } from '../test/fake-api.ts';
import { renderApp } from '../test/render.tsx';

const asset = (id: string, role: string, status = 'verified') => ({
  id,
  role: role as 'video_original',
  status: status as 'verified',
  mime: 'video/mp4',
  bytes: 1000,
  width: null,
  height: null,
  durationMs: 2000,
  failureReason: null,
});

describe('video memories', () => {
  it('[VID-005][VID-006] plays the web rendition inline with the poster, without autoplay', async () => {
    const api = installFakeApi({
      memories: [
        makeMemory({
          id: 'v1',
          kind: 'video',
          assets: [asset('orig', 'video_original'), asset('web', 'video_web')],
        }),
      ],
    });
    renderApp('/memories/v1');
    const video = await screen.findByLabelText('Video playback');
    expect(video).toHaveAttribute('src', 'https://media.test/v1/web?sig=1');
    expect(video).toHaveAttribute('poster', 'https://media.test/v1/display.jpg');
    expect(video).not.toHaveAttribute('autoplay');
    expect(api.calls('GET', '/v1/memories/v1/assets/orig/download')).toHaveLength(0);
    expect(screen.queryByRole('button', { name: 'Play motion' })).not.toBeInTheDocument();
  });

  it('[VID-001] falls back to the original while no rendition exists yet', async () => {
    installFakeApi({
      memories: [
        makeMemory({ id: 'v1', kind: 'video', assets: [asset('orig', 'video_original')] }),
      ],
    });
    renderApp('/memories/v1');
    expect(await screen.findByLabelText('Video playback')).toHaveAttribute(
      'src',
      'https://media.test/v1/orig?sig=1',
    );
  });

  it('offers the original for download and shows the poster until a video is playable', async () => {
    installFakeApi({
      memories: [
        makeMemory({
          id: 'v1',
          kind: 'video',
          assets: [asset('orig', 'video_original', 'uploading')],
        }),
      ],
    });
    renderApp('/memories/v1');
    await screen.findByRole('heading', { level: 1 });
    expect(screen.queryByLabelText('Video playback')).not.toBeInTheDocument();
    expect(screen.getByRole('img')).toHaveAttribute('src', 'https://media.test/v1/display.jpg');
  });
});

describe('data export', () => {
  const ready: DataExport = {
    id: 'e-1',
    status: 'ready',
    bytes: 5 * 1024 * 1024,
    createdAt: '2026-11-10T00:00:00.000Z',
    completedAt: '2026-11-10T00:01:00.000Z',
    expiresAt: '2026-11-17T00:00:00.000Z',
    failureReason: null,
    download: {
      url: 'https://media.test/export.zip',
      expiresAt: '2099-01-01T00:00:00.000Z',
      filename: 'doro-cam-export-2026-11-10.zip',
    },
  };

  it('[WEB-010] requests an export, shows that it is preparing, and disables a second request', async () => {
    const api = installFakeApi();
    const user = userEvent.setup();
    renderApp('/account');
    await user.click(await screen.findByRole('button', { name: 'Request data export' }));
    expect(await screen.findByText('Preparing your archive…')).toBeInTheDocument();
    expect(api.calls('POST', '/v1/me/exports')).toHaveLength(1);
    expect(screen.getByRole('button', { name: 'Request data export' })).toBeDisabled();
  });

  it('[WEB-010] polls while preparing and then offers the download with its size', async () => {
    const api = installFakeApi({
      exports: [{ ...ready, status: 'building', download: null, bytes: null }],
    });
    renderApp('/account');
    expect(await screen.findByText('Preparing your archive…')).toBeInTheDocument();
    api.state.exports = [ready];
    const link = await screen.findByRole('link', { name: 'Download (5 MB)' }, { timeout: 5000 });
    expect(link).toHaveAttribute('href', 'https://media.test/export.zip');
    expect(link).toHaveAttribute('download', 'doro-cam-export-2026-11-10.zip');
    expect(screen.getByRole('button', { name: 'Request data export' })).toBeEnabled();
  });

  it('[WEB-010] explains failed and expired exports', async () => {
    installFakeApi({
      exports: [
        { ...ready, id: 'e-2', status: 'failed', download: null, failureReason: 'disk full' },
        { ...ready, id: 'e-3', download: null },
      ],
    });
    renderApp('/account');
    expect(await screen.findByRole('alert')).toHaveTextContent('Failed: disk full. Try again.');
    expect(screen.getByText('Expired. Request a new export.')).toBeInTheDocument();
  });

  it('shows the server’s reason when an export cannot be requested', async () => {
    const api = installFakeApi();
    api.state.failures.set('POST /v1/me/exports', {
      status: 409,
      code: 'export.in_progress',
      message: 'An export is already being prepared.',
    });
    const user = userEvent.setup();
    renderApp('/account');
    await user.click(await screen.findByRole('button', { name: 'Request data export' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'An export is already being prepared.',
    );
  });
});

describe('social sign-in', () => {
  it('[AUTH-002][AUTH-003] shows no provider buttons unless the server enables them', async () => {
    installFakeApi({ signedIn: false });
    renderApp('/sign-in');
    await screen.findByRole('heading', { level: 1, name: 'Sign in' });
    expect(screen.queryByRole('button', { name: /Continue with/ })).not.toBeInTheDocument();
  });

  it('[AUTH-002] starts Google sign-in and follows the provider URL', async () => {
    const api = installFakeApi({ signedIn: false, socialProviders: ['google', 'apple'] });
    const assign = vi.fn();
    vi.stubGlobal('location', {
      origin: 'http://localhost:5173',
      pathname: '/sign-in',
      search: '',
      hash: '',
      assign,
    });
    const user = userEvent.setup();
    renderApp('/sign-in');
    expect(await screen.findByRole('button', { name: 'Continue with Apple' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Continue with Google' }));
    await waitFor(() => {
      expect(assign).toHaveBeenCalledWith(
        'https://accounts.google.com/o/oauth2/v2/auth?provider=google',
      );
    });
    expect(api.calls('POST', '/v1/auth/sign-in/social')[0]?.body).toEqual({
      provider: 'google',
      callbackURL: 'http://localhost:5173/',
    });
  });

  it('[AUTH-002] tells the user when the provider cannot be started', async () => {
    const api = installFakeApi({ signedIn: false, socialProviders: ['google'] });
    api.state.failures.set('POST /v1/auth/sign-in/social', {
      status: 400,
      code: 'PROVIDER_NOT_FOUND',
      message: 'Provider not found',
    });
    const user = userEvent.setup();
    renderApp('/sign-in');
    await user.click(await screen.findByRole('button', { name: 'Continue with Google' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Provider not found');
  });
});
