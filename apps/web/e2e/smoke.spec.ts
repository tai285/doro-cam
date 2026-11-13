import { expect, test } from '@playwright/test';

test.describe('web dashboard shell', () => {
  test('@cross a signed-out visitor is sent to sign in', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveURL(/\/sign-in$/);
    await expect(page).toHaveTitle('Sign in · Doro Cam');
    await expect(page.getByRole('heading', { level: 1, name: 'Sign in' })).toBeVisible();
    await expect(page.getByRole('navigation', { name: 'Primary' })).toBeVisible();
  });

  test('@cross shows a friendly page for unknown addresses', async ({ page }) => {
    await page.goto('/no/such/page');
    await expect(page.getByRole('heading', { level: 1, name: 'Page not found' })).toBeVisible();
  });

  test('[NFR-007] the skip link moves focus to the main content when activated', async ({
    page,
    isMobile,
  }) => {
    test.skip(isMobile, 'keyboard navigation applies to desktop browsers');
    await page.goto('/sign-in');
    const skip = page.getByRole('link', { name: 'Skip to main content' });
    await skip.focus();
    await expect(skip).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(page.locator('#main')).toBeFocused();
  });

  test('[NFR-007] the skip link is the first tab stop', async ({ page, isMobile, browserName }) => {
    test.skip(isMobile, 'keyboard navigation applies to desktop browsers');
    test.skip(browserName === 'webkit', 'Safari skips links when tabbing by default');
    await page.goto('/sign-in');
    await page.keyboard.press('Tab');
    await expect(page.getByRole('link', { name: 'Skip to main content' })).toBeFocused();
  });

  test('[NFR-007] has no horizontal scroll at phone width', async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 740 });
    await page.goto('/sign-in');
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });
});
