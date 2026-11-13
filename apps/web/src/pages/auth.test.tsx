import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { installFakeApi } from '../test/fake-api.ts';
import { renderApp } from '../test/render.tsx';

describe('sign in', () => {
  it('[WEB-001] signs in and lands on the library', async () => {
    const api = installFakeApi({ signedIn: false });
    const user = userEvent.setup();
    const { router } = renderApp('/sign-in');
    await user.type(await screen.findByLabelText('Email'), 'dorothy@example.test');
    await user.type(screen.getByLabelText('Password'), 'correct-password');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Your library' }),
    ).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/');
    expect(api.calls('POST', '/v1/auth/sign-in/email')[0]?.body).toEqual({
      email: 'dorothy@example.test',
      password: 'correct-password',
    });
  });

  it('[WEB-001] returns to the page the visitor was trying to open', async () => {
    installFakeApi({ signedIn: false });
    const user = userEvent.setup();
    const { router } = renderApp('/albums');
    await screen.findByRole('heading', { level: 1, name: 'Sign in' });
    await user.type(screen.getByLabelText('Email'), 'a@b.test');
    await user.type(screen.getByLabelText('Password'), 'correct-password');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    await screen.findByRole('heading', { level: 1, name: 'Albums' });
    expect(router.state.location.pathname).toBe('/albums');
  });

  it('[WEB-001] explains a wrong password in plain words and stays on the page', async () => {
    installFakeApi({ signedIn: false });
    const user = userEvent.setup();
    renderApp('/sign-in');
    await user.type(await screen.findByLabelText('Email'), 'a@b.test');
    await user.type(screen.getByLabelText('Password'), 'nope');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'That email and password do not match.',
    );
    expect(screen.getByRole('heading', { level: 1, name: 'Sign in' })).toBeInTheDocument();
  });

  it('[AUTH-001] tells an unverified user to check their email', async () => {
    installFakeApi({ signedIn: false });
    const user = userEvent.setup();
    renderApp('/sign-in');
    await user.type(await screen.findByLabelText('Email'), 'unverified@example.test');
    await user.type(screen.getByLabelText('Password'), 'correct-password');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('confirm your email address');
  });

  it('shows a network failure message when the server is unreachable', async () => {
    installFakeApi({ signedIn: false });
    const failing = (
      globalThis.fetch as unknown as {
        mockImplementationOnce: (fn: () => Promise<Response>) => void;
      }
    ).mockImplementationOnce;
    const user = userEvent.setup();
    renderApp('/sign-in');
    await screen.findByRole('heading', { level: 1, name: 'Sign in' });
    failing.call(globalThis.fetch, () => Promise.reject(new TypeError('Failed to fetch')));
    await user.type(screen.getByLabelText('Email'), 'a@b.test');
    await user.type(screen.getByLabelText('Password'), 'x');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not reach the server');
  });

  it('links to sign-up and password reset', async () => {
    installFakeApi({ signedIn: false });
    renderApp('/sign-in');
    expect(await screen.findByRole('link', { name: 'Forgot your password?' })).toHaveAttribute(
      'href',
      '/forgot-password',
    );
    expect(screen.getAllByRole('link', { name: /Create an account/ })[0]).toHaveAttribute(
      'href',
      '/sign-up',
    );
  });
});

describe('sign up', () => {
  it('[AUTH-001] creates an account and asks the user to check their email', async () => {
    const api = installFakeApi({ signedIn: false });
    const user = userEvent.setup();
    renderApp('/sign-up');
    await user.type(await screen.findByLabelText('Name'), 'Dorothy');
    await user.type(screen.getByLabelText('Email'), 'dorothy@example.test');
    await user.type(screen.getByLabelText('Password'), 'a-long-enough-password');
    await user.click(screen.getByRole('button', { name: 'Create account' }));
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Check your email' }),
    ).toBeInTheDocument();
    expect(screen.getByText('dorothy@example.test')).toBeInTheDocument();
    expect(api.calls('POST', '/v1/auth/sign-up/email')[0]?.body).toEqual({
      name: 'Dorothy',
      email: 'dorothy@example.test',
      password: 'a-long-enough-password',
    });
  });

  it('[AUTH-005] says the camera works without an account and states the password rule', async () => {
    installFakeApi({ signedIn: false });
    renderApp('/sign-up');
    expect(await screen.findByText(/work without an account/)).toBeInTheDocument();
    expect(screen.getByLabelText('Password')).toHaveAccessibleDescription(
      'At least 10 characters.',
    );
  });

  it('shows the server’s reason when sign-up is refused', async () => {
    const api = installFakeApi({ signedIn: false });
    api.state.failures.set('POST /v1/auth/sign-up/email', {
      status: 400,
      code: 'x',
      message: 'Password is too short',
    });
    const user = userEvent.setup();
    renderApp('/sign-up');
    await user.type(await screen.findByLabelText('Name'), 'D');
    await user.type(screen.getByLabelText('Email'), 'd@example.test');
    await user.type(screen.getByLabelText('Password'), 'short-ish-pw');
    await user.click(screen.getByRole('button', { name: 'Create account' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Password is too short');
  });
});

describe('password reset', () => {
  it('[AUTH-006] asks for an email and confirms without revealing whether the account exists', async () => {
    const api = installFakeApi({ signedIn: false });
    const user = userEvent.setup();
    renderApp('/forgot-password');
    await user.type(await screen.findByLabelText('Email'), 'who@example.test');
    await user.click(screen.getByRole('button', { name: 'Send reset link' }));
    expect(
      await screen.findByText(/If an account exists for who@example.test/),
    ).toBeInTheDocument();
    expect(api.calls('POST', '/v1/auth/request-password-reset')[0]?.body).toMatchObject({
      email: 'who@example.test',
      redirectTo: `${window.location.origin}/reset-password`,
    });
  });

  it('[AUTH-006] sets a new password using the token from the link', async () => {
    const api = installFakeApi({ signedIn: false });
    const user = userEvent.setup();
    renderApp('/reset-password?token=tok-123');
    await user.type(await screen.findByLabelText('New password'), 'a-brand-new-password');
    await user.click(screen.getByRole('button', { name: 'Update password' }));
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Password updated' }),
    ).toBeInTheDocument();
    expect(api.calls('POST', '/v1/auth/reset-password')[0]?.body).toEqual({
      token: 'tok-123',
      newPassword: 'a-brand-new-password',
    });
    expect(screen.getByRole('link', { name: /Sign in with your new password/ })).toHaveAttribute(
      'href',
      '/sign-in',
    );
  });

  it('[AUTH-006] a link without a token is explained, not an empty form', async () => {
    installFakeApi({ signedIn: false });
    renderApp('/reset-password');
    expect(
      await screen.findByRole('heading', { level: 1, name: 'This link is not valid' }),
    ).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getByRole('link', { name: 'reset page' })).toHaveAttribute(
        'href',
        '/forgot-password',
      );
    });
  });
});
