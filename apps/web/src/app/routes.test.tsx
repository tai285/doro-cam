import { screen } from '@testing-library/react';
import { axe } from '../test/axe.ts';
import { describe, expect, it } from 'vitest';
import { installFakeApi, makeAlbum, makeMemory, makePreset } from '../test/fake-api.ts';
import { renderApp } from '../test/render.tsx';

describe('routes (signed in)', () => {
  const memory = makeMemory({ id: '0191-abc', caption: 'Golden hour' });
  const album = makeAlbum({ id: 'album-1', title: 'Japan Trip' });
  const pages: ReadonlyArray<[string, string, string]> = [
    ['/', 'Your library', 'Library · Doro Cam'],
    ['/account', 'Account', 'Account · Doro Cam'],
    ['/albums', 'Albums', 'Albums · Doro Cam'],
    ['/albums/album-1', 'Japan Trip', 'Japan Trip · Doro Cam'],
    ['/insights', 'Insights', 'Insights · Doro Cam'],
    ['/presets', 'Presets', 'Presets · Doro Cam'],
    ['/memories/0191-abc', 'Golden hour', 'Golden hour · Doro Cam'],
    ['/invites/some-token', 'Join an album', 'Join album · Doro Cam'],
    ['/does/not/exist', 'Page not found', 'Page not found · Doro Cam'],
  ];
  const seed = () =>
    installFakeApi({
      memories: [memory],
      albums: [
        {
          album,
          members: [
            { userId: 'u-1', name: 'Dorothy', role: 'owner', joinedAt: '2026-11-01T00:00:00.000Z' },
          ],
          memoryIds: [],
        },
      ],
      presets: [makePreset()],
    });

  for (const [path, heading, title] of pages) {
    describe(path, () => {
      it(`shows the "${heading}" heading and sets the document title`, async () => {
        seed();
        renderApp(path);
        expect(await screen.findByRole('heading', { level: 1, name: heading })).toBeInTheDocument();
        expect(document.title).toBe(title);
      });

      it('[NFR-007] has no detectable accessibility violations', async () => {
        seed();
        const { container } = renderApp(path);
        await screen.findByRole('heading', { level: 1, name: heading });
        expect(await axe(container)).toHaveNoViolations();
      });

      it('[NFR-007] has exactly one h1 and one main landmark', async () => {
        seed();
        renderApp(path);
        await screen.findByRole('heading', { level: 1, name: heading });
        expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
        expect(screen.getAllByRole('main')).toHaveLength(1);
      });
    });
  }
});

describe('routes (signed out)', () => {
  const pages: ReadonlyArray<[string, string]> = [
    ['/sign-in', 'Sign in'],
    ['/sign-up', 'Create your account'],
    ['/forgot-password', 'Reset your password'],
    ['/reset-password?token=abc', 'Choose a new password'],
  ];
  for (const [path, heading] of pages) {
    it(`[NFR-007] ${path} is accessible and has one h1`, async () => {
      installFakeApi({ signedIn: false });
      const { container } = renderApp(path);
      await screen.findByRole('heading', { level: 1, name: heading });
      expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
      expect(await axe(container)).toHaveNoViolations();
    });
  }

  it('[PRIV-003] every protected page redirects to sign in', async () => {
    for (const path of [
      '/',
      '/account',
      '/albums',
      '/insights',
      '/presets',
      '/memories/x',
      '/albums/x',
      '/invites/x',
    ]) {
      installFakeApi({ signedIn: false });
      const { router, unmount } = renderApp(path);
      await screen.findByRole('heading', { level: 1, name: 'Sign in' });
      expect(router.state.location.pathname, path).toBe('/sign-in');
      unmount();
    }
  });

  it('the not-found page links to the library', async () => {
    installFakeApi();
    renderApp('/nowhere');
    expect(await screen.findByRole('link', { name: 'Go to your library' })).toHaveAttribute(
      'href',
      '/',
    );
  });
});
