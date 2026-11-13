import { expect, test } from '@playwright/test';
import { API, createUser, latestMail, ORIGIN, PASSWORD, signIn } from './helpers.ts';

test.describe('accounts', () => {
  test('@cross [AUTH-001][WEB-001] sign up, confirm the email, sign in, sign out', async ({
    page,
    request,
  }) => {
    const email = `signup-${String(Date.now())}-${Math.random().toString(16).slice(2, 6)}@example.test`;
    await page.goto('/sign-up');
    await page.getByLabel('Name').fill('Dorothy');
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(PASSWORD);
    await page.getByRole('button', { name: 'Create account' }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Check your email' })).toBeVisible();

    // Not verified yet: sign-in is refused with an explanation.
    await page.goto('/sign-in');
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(PASSWORD);
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
    await expect(page.getByRole('alert')).toContainText('confirm your email address');

    const mail = await latestMail(request, 'verify_email', email);
    await page.goto(mail.link);
    await signIn(page, { name: 'Dorothy', email, password: PASSWORD, token: '' });
    await expect(page.getByRole('navigation', { name: 'Primary' })).toContainText('Albums');

    await page.getByRole('link', { name: 'Account' }).click();
    await expect(page.getByText(`Dorothy · ${email}`)).toBeVisible();
    await page.getByRole('button', { name: 'Sign out', exact: true }).click();
    await expect(page).toHaveURL(/\/sign-in$/);
    await page.goto('/albums');
    await expect(page).toHaveURL(/\/sign-in$/);
  });

  test('@cross [WEB-001] a wrong password is explained and a signed-in session survives a reload', async ({
    page,
    request,
  }) => {
    const user = await createUser(request);
    await page.goto('/sign-in');
    await page.getByLabel('Email').fill(user.email);
    await page.getByLabel('Password').fill('definitely-not-it');
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
    await expect(page.getByRole('alert')).toHaveText('That email and password do not match.');
    await page.getByLabel('Password').fill(user.password);
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Your library' })).toBeVisible();
    await page.reload();
    await expect(page.getByRole('heading', { level: 1, name: 'Your library' })).toBeVisible();
  });

  test('[WEB-001] returns to the page the visitor first asked for', async ({ page, request }) => {
    const user = await createUser(request);
    await page.goto('/albums');
    await expect(page).toHaveURL(/\/sign-in$/);
    await page.getByLabel('Email').fill(user.email);
    await page.getByLabel('Password').fill(user.password);
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Albums' })).toBeVisible();
    await expect(page).toHaveURL(/\/albums$/);
  });

  test('[AUTH-006] reset the password from the emailed link, then sign in with the new one', async ({
    page,
    request,
  }) => {
    const user = await createUser(request);
    await page.goto('/forgot-password');
    await page.getByLabel('Email').fill(user.email);
    await page.getByRole('button', { name: 'Send reset link' }).click();
    await expect(
      page.getByText(new RegExp(`If an account exists for ${user.email}`)),
    ).toBeVisible();
    const mail = await latestMail(request, 'reset_password', user.email);
    await page.goto(mail.link);
    await expect(
      page.getByRole('heading', { level: 1, name: 'Choose a new password' }),
    ).toBeVisible();
    await page.getByLabel('New password', { exact: true }).fill('a-completely-new-password');
    await page.getByRole('button', { name: 'Update password' }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Password updated' })).toBeVisible();
    await signIn(page, { ...user, password: 'a-completely-new-password' });
    // the old password no longer works
    const old = await request.post(`${API}/v1/auth/sign-in/email`, {
      headers: { origin: ORIGIN },
      data: { email: user.email, password: user.password },
    });
    expect(old.status()).toBe(401);
  });

  test('[AUTH-004] revoking another device signs it out', async ({ page, request }) => {
    const user = await createUser(request);
    await signIn(page, user);
    // a "phone" session created through the API
    const phone = await request.post(`${API}/v1/auth/sign-in/email`, {
      data: { email: user.email, password: user.password },
      headers: { 'user-agent': 'Honor X9c phone', origin: ORIGIN },
    });
    const phoneToken = phone.headers()['set-auth-token'] as string;
    await page.getByRole('link', { name: 'Account' }).click();
    await expect(page.getByText('(this device)')).toBeVisible();
    await page.reload();
    const phoneRow = page.getByRole('listitem').filter({ hasText: 'Honor X9c phone' });
    await expect(phoneRow).toBeVisible();
    await phoneRow.getByRole('button', { name: 'Sign out this device' }).click();
    await expect(phoneRow).toHaveCount(0);
    const check = await request.get(`${API}/v1/me`, {
      headers: { authorization: `Bearer ${phoneToken}` },
    });
    expect(check.status()).toBe(401);
  });
});
