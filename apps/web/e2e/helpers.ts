import { createHash, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, type APIRequestContext, type Page } from '@playwright/test';

export const API = 'http://127.0.0.1:4300';
/** Better Auth checks the Origin of browser-style requests; the web app's origin is trusted. */
export const ORIGIN = 'http://127.0.0.1:4173';
export const PASSWORD = 'e2e-correct-horse-battery';

const here = path.dirname(fileURLToPath(import.meta.url));
export const fixture = (name: string): Buffer => readFileSync(path.join(here, 'fixtures', name));

export interface User {
  name: string;
  email: string;
  password: string;
  token: string;
}

interface Mail {
  kind: string;
  to: string;
  link: string;
}

/** The latest mail of a kind sent to an address (the API's e2e outbox; real inboxes are not available). */
export async function latestMail(
  request: APIRequestContext,
  kind: string,
  to: string,
): Promise<Mail> {
  let found: Mail | undefined;
  await expect
    .poll(async () => {
      const outbox = (await (await request.get(`${API}/__test/outbox`)).json()) as {
        items: Mail[];
      };
      found = outbox.items.filter((mail) => mail.kind === kind && mail.to === to).at(-1);
      return found !== undefined;
    })
    .toBe(true);
  return found as Mail;
}

/** Signs up, confirms the email through the mailed link and returns a bearer token, all through the real API. */
export async function createUser(request: APIRequestContext, name = 'E2E User'): Promise<User> {
  const email = `e2e-${randomUUID().slice(0, 8)}@example.test`;
  const signUp = await request.post(`${API}/v1/auth/sign-up/email`, {
    headers: { origin: ORIGIN },
    data: { name, email, password: PASSWORD },
  });
  expect(signUp.ok()).toBe(true);
  const mail = await latestMail(request, 'verify_email', email);
  // The link verifies the address and redirects to the app; the redirect target is not needed here.
  expect((await request.get(mail.link, { maxRedirects: 0 })).status()).toBeLessThan(400);
  const signIn = await request.post(`${API}/v1/auth/sign-in/email`, {
    headers: { origin: ORIGIN },
    data: { email, password: PASSWORD },
  });
  expect(signIn.ok(), `sign-in: ${String(signIn.status())} ${await signIn.text()}`).toBe(true);
  return { name, email, password: PASSWORD, token: signIn.headers()['set-auth-token'] as string };
}

const auth = (user: User) => ({ authorization: `Bearer ${user.token}` });

export function memoryBody(overrides: Record<string, unknown> = {}) {
  return {
    kind: 'photo',
    capturedAt: '2026-11-01T09:30:00.000Z',
    capturedTz: 'Asia/Kuala_Lumpur',
    experienceId: 'mirrorless',
    profile: { id: 'natural', version: 1 },
    scenario: 'street',
    capture: {
      lensKind: 'wide',
      focalLength35mmEq: 26,
      aperture: 1.8,
      isoApplied: 200,
      exposureTimeNsApplied: 8_000_000,
      widthPx: 640,
      heightPx: 480,
      deviceMake: 'Honor',
      deviceModel: 'X9c',
    },
    ...overrides,
  };
}

export async function registerMemory(
  request: APIRequestContext,
  user: User,
  overrides: Record<string, unknown> = {},
): Promise<string> {
  const id = randomUUID();
  const response = await request.put(`${API}/v1/memories/${id}`, {
    headers: auth(user),
    data: memoryBody(overrides),
  });
  expect(response.status()).toBe(201);
  return id;
}

/** The real upload protocol: create → presigned PUT straight to storage → complete (the worker verifies it). */
export async function uploadAsset(
  request: APIRequestContext,
  user: User,
  memoryId: string,
  role: string,
  mime: string,
  data: Buffer,
): Promise<string> {
  const assetId = randomUUID();
  const created = await request.post(`${API}/v1/memories/${memoryId}/assets/${assetId}/upload`, {
    headers: auth(user),
    data: {
      role,
      mime,
      bytes: data.length,
      sha256: createHash('sha256').update(data).digest('hex'),
    },
  });
  expect(created.status()).toBe(200);
  const plan = (await created.json()) as {
    mode: string;
    url?: string;
    headers?: Record<string, string>;
  };
  if (plan.mode === 'single') {
    const put = await fetch(plan.url as string, {
      method: 'PUT',
      headers: plan.headers ?? {},
      body: new Uint8Array(data),
    });
    expect(put.ok).toBe(true);
  }
  const done = await request.post(
    `${API}/v1/memories/${memoryId}/assets/${assetId}/upload/complete`,
    { headers: auth(user), data: {} },
  );
  expect(((await done.json()) as { status: string }).status).toBe('verified');
  return assetId;
}

/** A photo Memory with original, rendered image and thumbnail uploaded, as the app would leave it. */
export async function seedPhoto(
  request: APIRequestContext,
  user: User,
  overrides: Record<string, unknown> = {},
  imageName = 'photo.jpg',
): Promise<string> {
  const id = await registerMemory(request, user, overrides);
  await uploadAsset(request, user, id, 'photo_original', 'image/jpeg', fixture(imageName));
  await uploadAsset(request, user, id, 'photo_rendered', 'image/jpeg', fixture(imageName));
  await uploadAsset(request, user, id, 'thumbnail', 'image/jpeg', fixture('thumb.jpg'));
  return id;
}

export async function seedMotion(
  request: APIRequestContext,
  user: User,
  overrides: Record<string, unknown> = {},
): Promise<string> {
  const id = await registerMemory(request, user, { kind: 'motion', ...overrides });
  await uploadAsset(request, user, id, 'photo_original', 'image/jpeg', fixture('photo.jpg'));
  await uploadAsset(request, user, id, 'photo_rendered', 'image/jpeg', fixture('photo.jpg'));
  await uploadAsset(request, user, id, 'motion_clip', 'video/mp4', fixture('clip.mp4'));
  return id;
}

/** Signs in through the real sign-in form. */
export async function signIn(page: Page, user: User): Promise<void> {
  await page.goto('/sign-in');
  await page.getByLabel('Email').fill(user.email);
  await page.getByLabel('Password').fill(user.password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Your library' })).toBeVisible();
}

/** Axe rules run in the real browser, including color contrast (jsdom cannot check it). */
export async function expectNoAxeViolations(page: Page): Promise<void> {
  const axePath = path.join(here, '..', 'node_modules', 'axe-core', 'axe.min.js');
  await page.addScriptTag({ path: axePath });
  const violations = await page.evaluate(async () => {
    const result = await (
      window as unknown as {
        axe: {
          run: () => Promise<{
            violations: Array<{ id: string; help: string; nodes: Array<{ target: unknown }> }>;
          }>;
        };
      }
    ).axe.run();
    return result.violations.map((v) => ({
      id: v.id,
      help: v.help,
      targets: v.nodes.slice(0, 3).map((n) => String(n.target)),
    }));
  });
  expect(violations).toEqual([]);
}
