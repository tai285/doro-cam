import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { createUser, fixture, seedMotion, seedPhoto, signIn } from './helpers.ts';

test.describe('library and memories', () => {
  test('@cross [WEB-002][WEB-005] shows seeded memories newest first with storage usage', async ({
    page,
    request,
  }) => {
    const user = await createUser(request);
    await seedPhoto(request, user, {
      capturedAt: '2026-01-01T10:00:00.000Z',
      caption: 'Older one',
    });
    await seedPhoto(request, user, {
      capturedAt: '2026-06-01T10:00:00.000Z',
      caption: 'Newer one',
    });
    await signIn(page, user);
    const tiles = page.getByRole('list', { name: 'Memories' }).getByRole('link');
    await expect(tiles).toHaveCount(2);
    await expect(tiles.first().getByRole('img')).toHaveAttribute('alt', 'Newer one');
    await expect(page.getByText(/^Storage: .* of 10 GB used$/)).toBeVisible();
    // the image really loads from storage
    await expect
      .poll(() =>
        tiles
          .first()
          .getByRole('img')
          .evaluate((img: HTMLImageElement) => img.naturalWidth),
      )
      .toBeGreaterThan(0);
  });

  test('@cross [WEB-003][MEM-004][MEM-006] detail shows applied settings; caption and favorite persist', async ({
    page,
    request,
  }) => {
    const user = await createUser(request);
    const id = await seedPhoto(request, user, { caption: 'Pier' });
    await signIn(page, user);
    await page.goto(`/memories/${id}`);
    await expect(page.getByRole('heading', { level: 1, name: 'Pier' })).toBeVisible();
    const details = page.locator('dl.meta');
    await expect(details).toContainText('Honor X9c');
    await expect(details).toContainText('1/125 s');
    await expect(details).toContainText('f/1.8');
    await expect(details).toContainText('ISO');
    await expect(details).toContainText('26 mm');

    await page.getByLabel('Caption').fill('Golden hour at the pier');
    await page.getByRole('button', { name: 'Save caption' }).click();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Golden hour at the pier' }),
    ).toBeVisible();
    await page.getByRole('button', { name: '☆ Favorite' }).click();
    await expect(page.getByRole('button', { name: '★ Favorite' })).toBeVisible();
    await page.reload();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Golden hour at the pier' }),
    ).toBeVisible();
    await expect(page.getByRole('button', { name: '★ Favorite' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );

    await page.goto('/?view=favorites');
    await expect(page.getByRole('list', { name: 'Memories' }).getByRole('link')).toHaveCount(1);
  });

  test('[MEM-007] trash, restore, then delete permanently', async ({ page, request }) => {
    const user = await createUser(request);
    const id = await seedPhoto(request, user, { caption: 'Short lived' });
    await signIn(page, user);
    await page.goto(`/memories/${id}`);
    await page.getByRole('button', { name: 'Move to trash' }).click();
    await expect(page).toHaveURL(/\/$/);
    await expect(page.getByText(/No memories yet/)).toBeVisible();
    await page.getByRole('button', { name: 'Trash' }).click();
    await expect(page.getByRole('list', { name: 'Memories' }).getByRole('link')).toHaveCount(1);

    await page.goto(`/memories/${id}`);
    await expect(page.getByText(/In the trash/)).toBeVisible();
    await page.getByRole('button', { name: 'Restore' }).click();
    await expect(page.getByRole('button', { name: 'Move to trash' })).toBeVisible();

    await page.getByRole('button', { name: 'Move to trash' }).click();
    await page.goto(`/memories/${id}`);
    page.once('dialog', (dialog) => void dialog.accept());
    await page.getByRole('button', { name: 'Delete permanently' }).click();
    await expect(page).toHaveURL(/view=trash/);
    await expect(page.getByText('The trash is empty.')).toBeVisible();
    await page.goto(`/memories/${id}`);
    await expect(page.getByRole('heading', { level: 1, name: 'Memory not found' })).toBeVisible();
  });

  test('[WEB-004][NFR-005] downloads the original bit-exact', async ({ page, request }) => {
    const user = await createUser(request);
    const id = await seedPhoto(request, user, { caption: 'Download me' });
    await signIn(page, user);
    await page.goto(`/memories/${id}`);
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', { name: /Download original/ }).click();
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toMatch(/^photo_original-[0-9a-f]{8}\.jpg$/);
    const path = await download.path();
    expect(readFileSync(path).equals(fixture('photo.jpg'))).toBe(true);
  });

  test('[MOT-004][MOT-006] plays a Motion Memory in the browser, then returns to the still', async ({
    page,
    request,
    browserName,
  }) => {
    const user = await createUser(request);
    const id = await seedMotion(request, user, { caption: 'Live moment' });
    await signIn(page, user);
    await page.goto(`/memories/${id}`);
    await expect(page.getByText(/Motion Memory/)).toBeVisible();
    await page.getByRole('button', { name: 'Play motion' }).click();
    const video = page.getByLabel('Motion playback');
    await expect(video).toBeVisible();
    // the rendition the worker made is plain H.264/AAC MP4
    const src = await video.getAttribute('src');
    const bytes = await (await request.get(src as string)).body();
    expect(bytes.subarray(4, 8).toString()).toBe('ftyp');
    const canH264 = await page.evaluate(
      () =>
        document
          .createElement('video')
          .canPlayType('video/mp4; codecs="avc1.42E01E, mp4a.40.2"') !== '',
    );
    test.skip(
      !canH264,
      `${browserName} in this environment has no H.264 decoder; the rendition itself was verified above`,
    );
    await expect
      .poll(() => video.evaluate((v: HTMLVideoElement) => v.readyState))
      .toBeGreaterThanOrEqual(2);
    expect(await video.evaluate((v: HTMLVideoElement) => v.duration)).toBeGreaterThan(1);
    await video.evaluate((v: HTMLVideoElement) => {
      v.currentTime = Math.max(0, v.duration - 0.05);
    });
    await expect(page.getByRole('button', { name: 'Play motion' })).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByRole('img', { name: 'Live moment' })).toBeVisible();
  });
});
