import { afterAll, describe, expect, it } from 'vitest';
import { ConfigError, loadConfig } from '../src/config/env.ts';
import { startStack, type Stack } from './helpers/stack.ts';

const REQUIRED = {
  DATABASE_URL: 'postgres://user:pw@db.internal:5432/app',
  S3_ENDPOINT: 'https://s3.example.com',
  S3_BUCKET: 'my-bucket',
  S3_ACCESS_KEY_ID: 'AKIDEXAMPLE-KEY-ID',
  S3_SECRET_ACCESS_KEY: 'super-secret-access-key',
};

describe('social sign-in configuration', () => {
  it('[AUTH-002][AUTH-003] is off by default', () => {
    expect(loadConfig(REQUIRED).auth.social).toEqual({});
  });

  it('[AUTH-002] enables Google only when both id and secret are set', () => {
    expect(loadConfig({ ...REQUIRED, GOOGLE_CLIENT_ID: 'id', GOOGLE_CLIENT_SECRET: 'secret' }).auth.social).toEqual({ google: { clientId: 'id', clientSecret: 'secret' } });
    expect(() => loadConfig({ ...REQUIRED, GOOGLE_CLIENT_ID: 'id' })).toThrow(ConfigError);
    expect(() => loadConfig({ ...REQUIRED, GOOGLE_CLIENT_SECRET: 'secret' })).toThrow(/both the client id and the client secret/);
  });

  it('[AUTH-003] enables Apple with an optional app bundle identifier, and never echoes secrets in errors', () => {
    const config = loadConfig({ ...REQUIRED, APPLE_CLIENT_ID: 'com.dorocam.web', APPLE_CLIENT_SECRET: 'jwt', APPLE_APP_BUNDLE_IDENTIFIER: 'com.dorocam.app' });
    expect(config.auth.social.apple).toEqual({ clientId: 'com.dorocam.web', clientSecret: 'jwt', appBundleIdentifier: 'com.dorocam.app' });
    try {
      loadConfig({ ...REQUIRED, APPLE_CLIENT_SECRET: 'jwt-super-secret' });
      expect.unreachable();
    } catch (error) {
      expect((error as Error).message).not.toContain('jwt-super-secret');
    }
  });
});

describe('GET /v1/config', () => {
  const stacks: Stack[] = [];
  afterAll(async () => {
    await Promise.all(stacks.map((stack) => stack.close()));
  });

  it('[AUTH-002][AUTH-003] reports no social providers by default and rejects social sign-in', async () => {
    const stack = await startStack();
    stacks.push(stack);
    const response = await stack.app.inject({ method: 'GET', url: '/v1/config' });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ socialProviders: [], emailPassword: true });
    const attempt = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/social', payload: { provider: 'google', callbackURL: 'http://localhost:5173/' } });
    expect(attempt.statusCode).toBeGreaterThanOrEqual(400);
  });

  it('[AUTH-002][AUTH-003] lists configured providers and starts the OAuth redirect without leaking the secret', async () => {
    const stack = await startStack({ GOOGLE_CLIENT_ID: 'google-client-id.apps.test', GOOGLE_CLIENT_SECRET: 'google-secret-value', APPLE_CLIENT_ID: 'com.dorocam.web', APPLE_CLIENT_SECRET: 'apple-secret-jwt' });
    stacks.push(stack);
    expect((await stack.app.inject({ method: 'GET', url: '/v1/config' })).json()).toEqual({ socialProviders: ['google', 'apple'], emailPassword: true });
    const start = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/social', payload: { provider: 'google', callbackURL: 'http://localhost:5173/' } });
    expect(start.statusCode).toBe(200);
    const { url } = start.json() as { url: string };
    const target = new URL(url);
    expect(target.host).toBe('accounts.google.com');
    expect(target.searchParams.get('client_id')).toBe('google-client-id.apps.test');
    expect(url).not.toContain('google-secret-value');
  });
});
