import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createUser, PASSWORD, startStack, type Stack } from './helpers/stack.ts';

describe('auth, sessions and account', () => {
  let stack: Stack;

  beforeAll(async () => {
    stack = await startStack();
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[AUTH-001] sign-up sends a verification email and blocks sign-in until the address is verified', async () => {
    const email = 'new-person@example.test';
    const signUp = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-up/email', payload: { name: 'New Person', email, password: PASSWORD } });
    expect(signUp.statusCode).toBe(200);
    expect(stack.mailer.last('verify_email')?.to).toBe(email);

    const early = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/email', payload: { email, password: PASSWORD } });
    expect(early.statusCode).toBe(403);
    expect(early.headers['set-auth-token']).toBeUndefined();

    const link = new URL(stack.mailer.last('verify_email')!.link);
    const verified = await stack.app.inject({ method: 'GET', url: `${link.pathname}${link.search}` });
    expect(verified.statusCode).toBeLessThan(400);

    const signIn = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/email', payload: { email, password: PASSWORD } });
    expect(signIn.statusCode).toBe(200);
    expect(typeof signIn.headers['set-auth-token']).toBe('string');
  });

  it('[AUTH-001] rejects a weak password and a duplicate email', async () => {
    const weak = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-up/email', payload: { name: 'W', email: 'weak@example.test', password: 'short' } });
    expect(weak.statusCode).toBe(400);
    const user = await createUser(stack);
    const duplicate = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-up/email', payload: { name: 'Dup', email: user.email, password: PASSWORD } });
    // Sign-up answers the same way for an existing address so it cannot be used to find out who has an account.
    expect(duplicate.statusCode).toBe(200);
    const { rows } = await stack.database.pool.query('select count(*)::int as n from "user" where email = $1', [user.email]);
    expect(rows[0].n).toBe(1);
  });

  it('[AUTH-001] rejects a wrong password', async () => {
    const user = await createUser(stack);
    const wrong = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/email', payload: { email: user.email, password: 'not-the-password!' } });
    expect(wrong.statusCode).toBe(401);
  });

  it('[AUTH-006] password reset emails a link and the new password works', async () => {
    const user = await createUser(stack);
    const request = await stack.app.inject({
      method: 'POST',
      url: '/v1/auth/request-password-reset',
      payload: { email: user.email, redirectTo: 'http://localhost:5173/reset' },
    });
    expect(request.statusCode).toBe(200);
    const mail = stack.mailer.last('reset_password');
    expect(mail?.to).toBe(user.email);
    const token = new URL(mail!.link).pathname.split('/').pop()!;
    const reset = await stack.app.inject({ method: 'POST', url: '/v1/auth/reset-password', payload: { newPassword: 'a-brand-new-password', token } });
    expect(reset.statusCode).toBe(200);
    const signIn = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/email', payload: { email: user.email, password: 'a-brand-new-password' } });
    expect(signIn.statusCode).toBe(200);
  });

  it('[PRIV-003] every protected route answers 401 without a session', async () => {
    for (const [method, url] of [
      ['GET', '/v1/me'],
      ['GET', '/v1/me/sessions'],
      ['GET', '/v1/memories'],
      ['GET', '/v1/sync/changes'],
      ['GET', '/v1/presets'],
      ['GET', '/v1/albums'],
      ['GET', '/v1/insights/summary'],
    ] as const) {
      const response = await stack.app.inject({ method, url });
      expect(response.statusCode, `${method} ${url}`).toBe(401);
      expect((response.json() as { error: { code: string } }).error.code).toBe('auth.unauthenticated');
    }
  });

  it('[WEB-005] GET /v1/me returns the profile and storage usage', async () => {
    const user = await createUser(stack, 'Dorothy');
    const response = await stack.app.inject({ method: 'GET', url: '/v1/me', headers: user.headers });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      id: user.id,
      email: user.email,
      name: 'Dorothy',
      emailVerified: true,
      storage: { usedBytes: 0, quotaBytes: stack.config.limits.storageQuotaBytes },
      deletionRequestedAt: null,
    });
  });

  it('[AUTH-004] lists device sessions and revokes one; a revoked token stops working', async () => {
    const user = await createUser(stack);
    const second = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/email', payload: { email: user.email, password: user.password } });
    const secondHeaders = { authorization: `Bearer ${second.headers['set-auth-token'] as string}` };

    const list = await stack.app.inject({ method: 'GET', url: '/v1/me/sessions', headers: user.headers });
    const sessions = (list.json() as { items: Array<{ id: string; current: boolean }> }).items;
    expect(sessions.length).toBeGreaterThanOrEqual(2);
    expect(sessions.filter((s) => s.current)).toHaveLength(1);

    const secondList = await stack.app.inject({ method: 'GET', url: '/v1/me/sessions', headers: secondHeaders });
    const other = (secondList.json() as { items: Array<{ id: string; current: boolean }> }).items.find((s) => s.current)!;
    const revoke = await stack.app.inject({ method: 'DELETE', url: `/v1/me/sessions/${other.id}`, headers: user.headers });
    expect(revoke.statusCode).toBe(204);
    const afterRevoke = await stack.app.inject({ method: 'GET', url: '/v1/me', headers: secondHeaders });
    expect(afterRevoke.statusCode).toBe(401);
    const stillWorks = await stack.app.inject({ method: 'GET', url: '/v1/me', headers: user.headers });
    expect(stillWorks.statusCode).toBe(200);
  });

  it('[AUTH-004] cannot revoke another user’s session (answers 404)', async () => {
    const alice = await createUser(stack);
    const bob = await createUser(stack);
    const bobSessions = (await stack.app.inject({ method: 'GET', url: '/v1/me/sessions', headers: bob.headers })).json() as { items: Array<{ id: string }> };
    const attempt = await stack.app.inject({ method: 'DELETE', url: `/v1/me/sessions/${bobSessions.items[0]!.id}`, headers: alice.headers });
    expect(attempt.statusCode).toBe(404);
    expect((await stack.app.inject({ method: 'GET', url: '/v1/me', headers: bob.headers })).statusCode).toBe(200);
  });

  it('[PRIV-004][WEB-006] account deletion needs the password, can be cancelled, and runs after the grace period', async () => {
    const user = await createUser(stack);
    const wrong = await stack.app.inject({ method: 'POST', url: '/v1/me/deletion', headers: user.headers, payload: { password: 'wrong-password!!' } });
    expect(wrong.statusCode).toBe(403);
    expect((wrong.json() as { error: { code: string } }).error.code).toBe('auth.reauthentication_failed');

    const ok = await stack.app.inject({ method: 'POST', url: '/v1/me/deletion', headers: user.headers, payload: { password: user.password } });
    expect(ok.statusCode).toBe(200);
    const scheduled = new Date((ok.json() as { scheduledFor: string }).scheduledFor).getTime();
    expect(scheduled - Date.now()).toBeGreaterThan(6.9 * 86_400_000);

    const me = (await stack.app.inject({ method: 'GET', url: '/v1/me', headers: user.headers })).json() as { deletionRequestedAt: string | null };
    expect(me.deletionRequestedAt).not.toBeNull();

    const cancel = await stack.app.inject({ method: 'DELETE', url: '/v1/me/deletion', headers: user.headers });
    expect(cancel.statusCode).toBe(204);
    const after = (await stack.app.inject({ method: 'GET', url: '/v1/me', headers: user.headers })).json() as { deletionRequestedAt: string | null };
    expect(after.deletionRequestedAt).toBeNull();
  });
});
