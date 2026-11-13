import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { captureRows } from './MemoryPage.tsx';
import { installFakeApi, makeMemory } from '../test/fake-api.ts';
import { renderApp } from '../test/render.tsx';

describe('memory detail', () => {
  it('[WEB-003] shows the photo, caption as the heading and the capture settings that were actually applied', async () => {
    installFakeApi({
      memories: [
        makeMemory({
          id: 'm1',
          caption: 'Golden hour',
          profile: { id: 'warm-film', version: 2 },
          scenario: 'sunset',
          aspectRatio: '3:2',
          capture: {
            deviceMake: 'Honor',
            deviceModel: 'X9c',
            lensKind: 'wide',
            focalLength35mmEq: 26,
            aperture: 1.8,
            exposureTimeNsApplied: 8_000_000,
            isoApplied: 200,
            exposureBiasEv: -0.7,
            flash: 'auto',
            widthPx: 4000,
            heightPx: 3000,
          },
        }),
      ],
    });
    renderApp('/memories/m1');
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Golden hour' }),
    ).toBeInTheDocument();
    expect(screen.getByRole('img', { name: 'Golden hour' })).toHaveAttribute(
      'src',
      'https://media.test/m1/display.jpg',
    );
    expect(screen.getByText(/Shot 1 Nov 2026/)).toHaveTextContent('Asia/Kuala_Lumpur');
    const details = screen.getByText('Camera').closest('dl') as HTMLElement;
    const row = (term: string) => within(details).getByText(term).nextElementSibling?.textContent;
    expect(row('Camera')).toBe('Honor X9c');
    expect(row('Focal length (35 mm equivalent)')).toBe('26 mm');
    expect(row('Aperture')).toBe('f/1.8');
    expect(row('Shutter')).toBe('1/125 s');
    expect(row('ISO')).toBe('200');
    expect(row('Exposure compensation')).toBe('-0.7 EV');
    expect(row('Flash')).toBe('Auto');
    expect(row('Size')).toBe('4000 × 3000');
    expect(row('Profile')).toBe('warm-film');
    expect(row('Scenario')).toBe('sunset');
    expect(row('Aspect ratio')).toBe('3:2');
  });

  it('captureRows only lists what the device reported and formats shutters and exposure bias', () => {
    const rows = captureRows(
      makeMemory({
        capture: { exposureTimeNsApplied: 2_000_000_000, exposureBiasEv: 1, flash: 'weird' },
        profile: null,
      }),
    );
    expect(rows).toEqual([
      ['Shutter', '2 s'],
      ['Exposure compensation', '+1 EV'],
      ['Flash', 'weird'],
      ['Experience', 'mirrorless'],
    ]);
  });

  it('[WEB-003] shows a clear message when the photo is not found (or not yours)', async () => {
    installFakeApi();
    renderApp('/memories/nope');
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Memory not found' }, { timeout: 4000 }),
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Back to your library' })).toHaveAttribute('href', '/');
  });

  it('shows a retryable error when the memory fails to load for another reason', async () => {
    const api = installFakeApi({ memories: [makeMemory({ id: 'm1' })] });
    api.state.failures.set('GET /v1/memories/m1', {
      status: 500,
      code: 'internal',
      message: 'Boom',
    });
    renderApp('/memories/m1');
    expect(
      await screen.findByRole('heading', { level: 1, name: 'We couldn’t load this memory' }),
    ).toBeInTheDocument();
  });

  it('says so while the display image has not been uploaded yet', async () => {
    installFakeApi({ memories: [makeMemory({ id: 'm1', display: null })] });
    renderApp('/memories/m1');
    expect(await screen.findByText('This photo is still uploading.')).toBeInTheDocument();
  });

  it('[MEM-004] saves a caption, and clearing it sends null', async () => {
    const api = installFakeApi({ memories: [makeMemory({ id: 'm1', caption: 'Old' })] });
    const user = userEvent.setup();
    renderApp('/memories/m1');
    const box = await screen.findByLabelText('Caption');
    await user.clear(box);
    await user.type(box, '  New words  ');
    await user.click(screen.getByRole('button', { name: 'Save caption' }));
    await waitFor(() => {
      expect(api.calls('PATCH', '/v1/memories/m1')[0]?.body).toEqual({ caption: 'New words' });
    });
    expect(await screen.findByRole('heading', { level: 1, name: 'New words' })).toBeInTheDocument();
    await user.clear(screen.getByLabelText('Caption'));
    await user.click(screen.getByRole('button', { name: 'Save caption' }));
    await waitFor(() => {
      expect(api.calls('PATCH', '/v1/memories/m1')[1]?.body).toEqual({ caption: null });
    });
  });

  it('[MEM-006] toggles favorite', async () => {
    const api = installFakeApi({ memories: [makeMemory({ id: 'm1' })] });
    const user = userEvent.setup();
    renderApp('/memories/m1');
    await user.click(await screen.findByRole('button', { name: '☆ Favorite' }));
    await waitFor(() => {
      expect(api.calls('PATCH', '/v1/memories/m1')[0]?.body).toEqual({ favorite: true });
    });
    expect(await screen.findByRole('button', { name: '★ Favorite' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
  });

  it('[PRIV-001] lets the owner remove the location', async () => {
    const api = installFakeApi({
      memories: [makeMemory({ id: 'm1', location: { lat: 3.139, lon: 101.6869, accuracyM: 5 } })],
    });
    const user = userEvent.setup();
    renderApp('/memories/m1');
    expect(await screen.findByText('3.1390, 101.6869')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Remove location' }));
    await waitFor(() => {
      expect(api.calls('PATCH', '/v1/memories/m1')[0]?.body).toEqual({ removeLocation: true });
    });
    await waitFor(() => {
      expect(screen.queryByText('3.1390, 101.6869')).not.toBeInTheDocument();
    });
  });

  it('[MEM-007] moves to the trash and returns to the library', async () => {
    const api = installFakeApi({ memories: [makeMemory({ id: 'm1' })] });
    const user = userEvent.setup();
    const { router } = renderApp('/memories/m1');
    await user.click(await screen.findByRole('button', { name: 'Move to trash' }));
    await waitFor(() => {
      expect(api.calls('POST', '/v1/memories/m1/trash')).toHaveLength(1);
    });
    await waitFor(() => {
      expect(router.state.location.pathname).toBe('/');
    });
  });

  it('[MEM-007] a trashed memory can be restored or deleted permanently after confirmation', async () => {
    const api = installFakeApi({
      memories: [makeMemory({ id: 'm1', deletedAt: '2026-11-10T00:00:00.000Z' })],
    });
    const confirm = vi
      .spyOn(window, 'confirm')
      .mockReturnValueOnce(false)
      .mockReturnValueOnce(true);
    const user = userEvent.setup();
    const { router } = renderApp('/memories/m1');
    expect(await screen.findByText(/In the trash/)).toBeInTheDocument();
    expect(screen.queryByLabelText('Caption')).not.toBeInTheDocument(); // no editing in the trash
    await user.click(screen.getByRole('button', { name: 'Delete permanently' }));
    expect(api.calls('DELETE', '/v1/memories/m1')).toHaveLength(0);
    await user.click(screen.getByRole('button', { name: 'Delete permanently' }));
    await waitFor(() => {
      expect(api.calls('DELETE', '/v1/memories/m1')).toHaveLength(1);
    });
    await waitFor(() => {
      expect(router.state.location.search).toBe('?view=trash');
    });
    expect(confirm).toHaveBeenCalledTimes(2);
  });

  it('[MEM-007] restoring brings the memory back', async () => {
    const api = installFakeApi({
      memories: [makeMemory({ id: 'm1', deletedAt: '2026-11-10T00:00:00.000Z' })],
    });
    const user = userEvent.setup();
    renderApp('/memories/m1');
    await user.click(await screen.findByRole('button', { name: 'Restore' }));
    await waitFor(() => {
      expect(api.calls('POST', '/v1/memories/m1/restore')).toHaveLength(1);
    });
    expect(await screen.findByRole('button', { name: 'Move to trash' })).toBeInTheDocument();
  });

  it('[WEB-004] downloads the original through a short-lived link', async () => {
    const api = installFakeApi({ memories: [makeMemory({ id: 'm1' })] });
    const click = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(() => undefined);
    const user = userEvent.setup();
    renderApp('/memories/m1');
    await user.click(await screen.findByRole('button', { name: 'Download original (2.38 MB)' }));
    await waitFor(() => {
      expect(click).toHaveBeenCalledTimes(1);
    });
    expect(api.calls('GET', '/v1/memories/m1/assets/m1-orig/download')).toHaveLength(1);
    const anchor = click.mock.contexts[0] as HTMLAnchorElement;
    expect(anchor.href).toBe('https://media.test/m1/m1-orig?sig=1');
    expect(anchor.download).toBe('photo_original-0000.jpg');
  });

  it('[WEB-004] offers no download until the original is verified', async () => {
    installFakeApi({
      memories: [
        makeMemory({
          id: 'm1',
          assets: [
            {
              id: 'a',
              role: 'photo_original',
              status: 'uploading',
              mime: 'image/jpeg',
              bytes: 10,
              width: null,
              height: null,
              durationMs: null,
              failureReason: null,
            },
          ],
        }),
      ],
    });
    renderApp('/memories/m1');
    await screen.findByRole('heading', { level: 1 });
    expect(screen.queryByRole('button', { name: /Download original/ })).not.toBeInTheDocument();
  });

  it('[PRIV-002] a member sees someone else’s memory read-only, without editing or trash controls', async () => {
    installFakeApi({
      memories: [makeMemory({ id: 'm1', isOwner: false, ownerId: 'someone-else', location: null })],
    });
    renderApp('/memories/m1');
    await screen.findByRole('heading', { level: 1 });
    expect(screen.queryByLabelText('Caption')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Move to trash' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Favorite/ })).not.toBeInTheDocument();
    expect(screen.queryByText('Location')).not.toBeInTheDocument();
  });

  it('sanitized media of other people’s memories is requested from the API origin', async () => {
    installFakeApi({
      memories: [
        makeMemory({
          id: 'm1',
          isOwner: false,
          display: {
            url: '/v1/memories/m1/assets/a1/content',
            expiresAt: '2099-01-01T00:00:00.000Z',
          },
        }),
      ],
    });
    renderApp('/memories/m1');
    const image = await screen.findByRole('img');
    expect(image.getAttribute('src')).toBe(
      'http://localhost:3000/v1/memories/m1/assets/a1/content',
    );
  });

  describe('Motion Memories', () => {
    const motion = (overrides = {}) =>
      makeMemory({
        id: 'live1',
        kind: 'motion',
        assets: [
          {
            id: 'orig',
            role: 'photo_original',
            status: 'verified',
            mime: 'image/jpeg',
            bytes: 1000,
            width: null,
            height: null,
            durationMs: null,
            failureReason: null,
          },
          {
            id: 'clip',
            role: 'motion_clip',
            status: 'verified',
            mime: 'video/mp4',
            bytes: 5000,
            width: null,
            height: null,
            durationMs: 3000,
            failureReason: null,
          },
        ],
        ...overrides,
      });

    it('[MOT-004][MOT-006] plays the motion on demand, then returns to the still when it ends', async () => {
      const api = installFakeApi({ memories: [motion()] });
      const user = userEvent.setup();
      renderApp('/memories/live1');
      expect(await screen.findByText(/Motion Memory/)).toBeInTheDocument();
      await user.click(await screen.findByRole('button', { name: 'Play motion' }));
      const video = await screen.findByLabelText('Motion playback');
      expect(video).toHaveAttribute('src', 'https://media.test/live1/clip?sig=1');
      expect(video).toHaveAttribute('poster', 'https://media.test/live1/display.jpg');
      expect(api.calls('GET', '/v1/memories/live1/assets/clip/download')).toHaveLength(1);
      video.dispatchEvent(new Event('ended'));
      await waitFor(() => {
        expect(screen.queryByLabelText('Motion playback')).not.toBeInTheDocument();
      });
      expect(screen.getByRole('img', { name: /Motion memory/ })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Play motion' })).toBeInTheDocument();
    });

    it('[MOT-006] prefers the browser-compatible rendition when the worker made one', async () => {
      const api = installFakeApi({
        memories: [
          motion({
            assets: [
              {
                id: 'clip',
                role: 'motion_clip',
                status: 'verified',
                mime: 'video/quicktime',
                bytes: 5000,
                width: null,
                height: null,
                durationMs: null,
                failureReason: null,
              },
              {
                id: 'web',
                role: 'motion_web',
                status: 'ready',
                mime: 'video/mp4',
                bytes: 3000,
                width: null,
                height: null,
                durationMs: null,
                failureReason: null,
              },
            ],
          }),
        ],
      });
      const user = userEvent.setup();
      renderApp('/memories/live1');
      await user.click(await screen.findByRole('button', { name: 'Play motion' }));
      await screen.findByLabelText('Motion playback');
      expect(api.calls('GET', '/v1/memories/live1/assets/web/download')).toHaveLength(1);
      expect(api.calls('GET', '/v1/memories/live1/assets/clip/download')).toHaveLength(0);
    });

    it('lets the viewer go back to the photo before the clip ends', async () => {
      installFakeApi({ memories: [motion()] });
      const user = userEvent.setup();
      renderApp('/memories/live1');
      await user.click(await screen.findByRole('button', { name: 'Play motion' }));
      await user.click(await screen.findByRole('button', { name: 'Back to photo' }));
      expect(screen.queryByLabelText('Motion playback')).not.toBeInTheDocument();
    });

    it('offers no play button until the clip is verified', async () => {
      installFakeApi({
        memories: [
          motion({
            assets: [
              {
                id: 'clip',
                role: 'motion_clip',
                status: 'uploading',
                mime: 'video/mp4',
                bytes: 5000,
                width: null,
                height: null,
                durationMs: null,
                failureReason: null,
              },
            ],
          }),
        ],
      });
      renderApp('/memories/live1');
      await screen.findByRole('heading', { level: 1 });
      expect(screen.queryByRole('button', { name: 'Play motion' })).not.toBeInTheDocument();
    });
  });
});
