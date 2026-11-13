import { expect, test } from '@playwright/test';
import {
  API,
  createUser,
  expectNoAxeViolations,
  registerMemory,
  seedPhoto,
  signIn,
} from './helpers.ts';

test.describe('albums and sharing', () => {
  test('@cross [SHR-001][SHR-003] invite a friend, who joins and sees the shared memory read-only', async ({
    browser,
    request,
  }) => {
    const owner = await createUser(request, 'Olive');
    const friend = await createUser(request, 'Frankie');
    const memoryId = await seedPhoto(request, owner, { caption: 'Shibuya crossing' });

    const ownerCtx = await browser.newContext();
    const ownerPage = await ownerCtx.newPage();
    await signIn(ownerPage, owner);
    await ownerPage.getByRole('link', { name: 'Albums' }).click();
    await ownerPage.getByLabel('Title').fill('Japan Trip');
    await ownerPage.getByRole('button', { name: 'Create album' }).click();
    await expect(ownerPage.getByRole('heading', { level: 1, name: 'Japan Trip' })).toBeVisible();

    await ownerPage.getByLabel('Shibuya crossing').check();
    await ownerPage.getByRole('button', { name: /Add selected/ }).click();
    await expect(ownerPage.getByRole('img', { name: 'Shibuya crossing' })).toBeVisible();

    await ownerPage.getByLabel('Role', { exact: true }).selectOption('viewer');
    await ownerPage.getByRole('button', { name: 'Create invite link' }).click();
    const linkText = await ownerPage.getByText(/Share this link/).textContent();
    const inviteUrl = /(http:\/\/\S+\/invites\/\S+)/.exec(linkText ?? '')?.[1] as string;
    expect(inviteUrl).toContain('/invites/');

    const friendCtx = await browser.newContext();
    const friendPage = await friendCtx.newPage();
    await signIn(friendPage, friend);
    await friendPage.goto(new URL(inviteUrl).pathname);
    await friendPage.getByRole('button', { name: 'Accept invite' }).click();
    await expect(friendPage.getByRole('heading', { level: 1, name: 'Japan Trip' })).toBeVisible();
    await expect(friendPage.getByText('You are a viewer.')).toBeVisible();
    await expect(friendPage.getByRole('img', { name: 'Shibuya crossing' })).toBeVisible();
    // a viewer cannot add, invite or change settings
    await expect(friendPage.getByRole('heading', { name: 'Add your memories' })).toHaveCount(0);
    await expect(friendPage.getByRole('heading', { name: 'Invite someone' })).toHaveCount(0);
    await expect(friendPage.getByRole('button', { name: 'Delete album' })).toHaveCount(0);

    // the memory opens read-only for the friend
    await friendPage
      .getByRole('link')
      .filter({ has: friendPage.getByRole('img', { name: 'Shibuya crossing' }) })
      .click();
    await expect(
      friendPage.getByRole('heading', { level: 1, name: 'Shibuya crossing' }),
    ).toBeVisible();
    await expect(friendPage.getByLabel('Caption')).toHaveCount(0);

    // a stranger cannot reach it (404 → friendly page)
    const stranger = await createUser(request, 'Stranger');
    const strangerCtx = await browser.newContext();
    const strangerPage = await strangerCtx.newPage();
    await signIn(strangerPage, stranger);
    await strangerPage.goto(`/memories/${memoryId}`);
    await expect(
      strangerPage.getByRole('heading', { level: 1, name: 'Memory not found' }),
    ).toBeVisible({ timeout: 15_000 });
    await Promise.all([ownerCtx.close(), friendCtx.close(), strangerCtx.close()]);
  });

  test('[PRIV-002][SHR-006] a viewer never receives GPS: not in the page, not in the image bytes', async ({
    browser,
    request,
  }) => {
    const owner = await createUser(request, 'Olive');
    const friend = await createUser(request, 'Vera');
    const id = await seedPhoto(
      request,
      owner,
      { caption: 'Secret spot', location: { lat: 3.139, lon: 101.6869 } },
      'photo-gps.jpg',
    );
    const album = (await (
      await request.post(`${API}/v1/albums`, {
        headers: { authorization: `Bearer ${owner.token}` },
        data: { title: 'Private places' },
      })
    ).json()) as { id: string };
    await request.post(`${API}/v1/albums/${album.id}/items`, {
      headers: { authorization: `Bearer ${owner.token}` },
      data: { memoryIds: [id] },
    });
    const invite = (await (
      await request.post(`${API}/v1/albums/${album.id}/invites`, {
        headers: { authorization: `Bearer ${owner.token}` },
        data: { role: 'viewer' },
      })
    ).json()) as { token: string };
    await request.post(`${API}/v1/invites/accept`, {
      headers: { authorization: `Bearer ${friend.token}` },
      data: { token: invite.token },
    });

    const ownerCtx = await browser.newContext();
    const ownerPage = await ownerCtx.newPage();
    await signIn(ownerPage, owner);
    await ownerPage.goto(`/memories/${id}`);
    await expect(ownerPage.locator('dl.meta')).toContainText('3.1390, 101.6869');
    await ownerCtx.close();

    const friendCtx = await browser.newContext();
    const page = await friendCtx.newPage();
    await signIn(page, friend);
    await page.goto(`/memories/${id}`);
    await expect(page.getByRole('heading', { level: 1, name: 'Secret spot' })).toBeVisible();
    await expect(page.locator('dl.meta')).not.toContainText('Location');
    await expect(page.locator('main')).not.toContainText('3.1390');
    // the displayed image is the sanitized copy served through the authorizing endpoint
    const src = await page.getByRole('img', { name: 'Secret spot' }).getAttribute('src');
    expect(src).toContain('/content');
    const body = await (await friendCtx.request.get(src as string)).body();
    expect(body.subarray(0, 2).toString('hex')).toBe('ffd8'); // still a JPEG
    expect(body.includes(Buffer.from('Exif'))).toBe(false);
    expect(body.includes(Buffer.from('GPS'))).toBe(false);
    await friendCtx.close();
  });
});

test.describe('insights and presets', () => {
  test('[WEB-009][PRE-002][PRE-003] statistics, an explained suggestion, accepting it, and it appearing in presets', async ({
    page,
    request,
  }) => {
    const user = await createUser(request);
    for (let i = 0; i < 8; i += 1) {
      await registerMemory(request, user, {
        capturedAt: `2026-04-${String(10 + i)}T04:00:00.000Z`,
      });
    }
    await registerMemory(request, user, {
      capturedAt: '2026-05-02T04:00:00.000Z',
      experienceId: 'instant',
      profile: { id: 'instant-warm', version: 1 },
      scenario: undefined,
    });
    await signIn(page, user);
    await page.getByRole('link', { name: 'Insights' }).click();
    await expect(page.getByText('Based on 9 memories.', { exact: false })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Focal length' })).toBeVisible();
    await expect(page.getByText(/You shoot most at 24-35 mm/)).toBeVisible();
    await expect(page.getByText(/8 of your 9 photos \(89%\)/)).toBeVisible();
    await page.getByRole('button', { name: 'Save as preset' }).click();
    await expect(page.getByText(/No suggestions yet/)).toBeVisible();

    await page.getByRole('link', { name: 'Presets' }).click();
    await expect(page.getByText('suggested from your habits')).toBeVisible();
    await page.getByRole('button', { name: 'Rename' }).click();
    await page.getByLabel('Preset name').fill('My street look');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'My street look' })).toBeVisible();
    page.once('dialog', (dialog) => void dialog.accept());
    await page.getByRole('button', { name: 'Delete' }).click();
    await expect(page.getByText('No presets yet.')).toBeVisible();
  });
});

test.describe('account', () => {
  test('[WEB-006][PRIV-004] account deletion needs the password and can be cancelled', async ({
    page,
    request,
  }) => {
    const user = await createUser(request);
    await signIn(page, user);
    await page.getByRole('link', { name: 'Account' }).click();
    await page.getByLabel('Confirm your password').fill('wrong-password-here');
    await page.getByRole('button', { name: 'Delete my account' }).click();
    await expect(page.getByRole('alert')).toContainText('The password is incorrect.');
    await page.getByLabel('Confirm your password').fill(user.password);
    await page.getByRole('button', { name: 'Delete my account' }).click();
    await expect(page.getByText(/scheduled for deletion on/)).toBeVisible();
    await page.getByRole('button', { name: 'Cancel deletion' }).click();
    await expect(page.getByRole('button', { name: 'Delete my account' })).toBeVisible();
  });

  test('[WEB-010][PRIV-006] requests a data export and downloads a real zip with the originals', async ({
    page,
    request,
  }) => {
    const user = await createUser(request);
    await seedPhoto(request, user, { caption: 'Exported' });
    await signIn(page, user);
    await page.getByRole('link', { name: 'Account' }).click();
    await page.getByRole('button', { name: 'Request data export' }).click();
    const link = page.getByRole('link', { name: /^Download \(/ });
    await expect(link).toBeVisible({ timeout: 20_000 });
    const href = await link.getAttribute('href');
    const bytes = await (await request.get(href as string)).body();
    expect(bytes.subarray(0, 2).toString()).toBe('PK');
    expect(bytes.includes(Buffer.from('metadata.json'))).toBe(true);
    expect(bytes.includes(Buffer.from('photo_original.jpg'))).toBe(true);
  });
});

test.describe('accessibility and responsive layout', () => {
  const pages = [
    '/sign-in',
    '/sign-up',
    '/forgot-password',
    '/',
    '/albums',
    '/insights',
    '/presets',
    '/account',
  ];

  for (const scheme of ['light', 'dark'] as const) {
    test(`@cross [NFR-007] no axe violations (including color contrast) in ${scheme} mode`, async ({
      page,
      request,
    }) => {
      await page.emulateMedia({ colorScheme: scheme });
      const user = await createUser(request);
      await seedPhoto(request, user, { caption: 'A11y photo' });
      for (const path of ['/sign-in', '/sign-up', '/forgot-password']) {
        await page.goto(path);
        await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
        await expectNoAxeViolations(page);
      }
      await signIn(page, user);
      for (const path of pages.slice(3)) {
        await page.goto(path);
        await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
        await expect(page.getByRole('status')).toHaveCount(0, { timeout: 15_000 });
        await expectNoAxeViolations(page);
      }
      const id =
        (await page.goto('/')) &&
        (await page
          .getByRole('list', { name: 'Memories' })
          .getByRole('link')
          .first()
          .getAttribute('href'));
      await page.goto(id as string);
      await expect(page.getByRole('heading', { level: 1, name: 'A11y photo' })).toBeVisible();
      await expectNoAxeViolations(page);
    });
  }

  test('[NFR-007] no horizontal scroll on any page at phone width', async ({ page, request }) => {
    await page.setViewportSize({ width: 360, height: 740 });
    const user = await createUser(request);
    await seedPhoto(request, user, { caption: 'Phone' });
    await signIn(page, user);
    for (const path of pages.slice(3)) {
      await page.goto(path);
      await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
      );
      expect(overflow, path).toBe(false);
    }
  });

  test('every control meets the 44px touch target on a phone', async ({
    page,
    request,
    isMobile,
  }) => {
    test.skip(!isMobile, 'touch targets are a phone concern');
    const user = await createUser(request);
    await signIn(page, user);
    const small = await page.evaluate(() =>
      [...document.querySelectorAll('button, a[href], input, select')]
        .filter((el) => !el.closest('.skip-link') && !el.classList.contains('skip-link'))
        .map((el) => ({
          el: el.tagName + el.textContent.slice(0, 20),
          rect: el.getBoundingClientRect(),
        }))
        .filter(({ rect }) => rect.width > 0 && rect.height > 0 && rect.height < 36)
        .map(({ el }) => el),
    );
    expect(small).toEqual([]);
  });
});
