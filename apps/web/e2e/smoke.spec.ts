import { expect, test } from '@playwright/test';

test.describe('web dashboard shell', () => {
  test('loads the library and shows the product name', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle('Library · Doro Cam');
    await expect(page.getByRole('heading', { level: 1, name: 'Your library' })).toBeVisible();
    await expect(page.getByRole('navigation', { name: 'Primary' })).toBeVisible();
  });

  test('navigates between pages and keeps the URL in sync', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('link', { name: 'Account' }).click();
    await expect(page).toHaveURL(/\/account$/);
    await expect(page.getByRole('heading', { level: 1, name: 'Account' })).toBeVisible();
    await expect(page).toHaveTitle('Account · Doro Cam');

    await page.goBack();
    await expect(page.getByRole('heading', { level: 1, name: 'Your library' })).toBeVisible();
  });

  test('serves the app for deep links (single-page fallback)', async ({ page }) => {
    await page.goto('/memories/abc-123');
    await expect(page.getByText('abc-123')).toBeVisible();
  });

  test('shows a friendly page for unknown addresses', async ({ page }) => {
    await page.goto('/no/such/page');
    await expect(page.getByRole('heading', { level: 1, name: 'Page not found' })).toBeVisible();
    await page.getByRole('link', { name: 'Go to your library' }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Your library' })).toBeVisible();
  });

  test('[NFR-007] the skip link moves focus to the main content when activated', async ({
    page,
    isMobile,
  }) => {
    test.skip(isMobile, 'keyboard navigation applies to desktop browsers');
    await page.goto('/');
    const skip = page.getByRole('link', { name: 'Skip to main content' });
    await skip.focus();
    await expect(skip).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(page.locator('#main')).toBeFocused();
  });

  test('[NFR-007] the skip link is the first tab stop', async ({ page, isMobile, browserName }) => {
    test.skip(isMobile, 'keyboard navigation applies to desktop browsers');
    // Safari does not Tab onto links by default (it needs Option+Tab), so this cannot be asserted in WebKit.
    test.skip(browserName === 'webkit', 'Safari skips links when tabbing by default');
    await page.goto('/');
    await page.keyboard.press('Tab');
    await expect(page.getByRole('link', { name: 'Skip to main content' })).toBeFocused();
  });

  test('[NFR-007] has no horizontal scroll at phone width', async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 740 });
    await page.goto('/');
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });
});
