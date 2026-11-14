import { randomUUID } from 'node:crypto';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';

/**
 * The web half of the full-stack scenario (scripts/e2e-fullstack.sh): the Memories the Android app captured and
 * uploaded through the real API + worker + storage show up in the dashboard, the motion clip is a real MP4,
 * and the owner shares an album with a second account. Run only through the script, which sets FULLSTACK_*.
 */
const API = process.env.FULLSTACK_API ?? 'http://127.0.0.1:4311';
const ORIGIN = process.env.FULLSTACK_WEB ?? 'http://127.0.0.1:4173';
const EMAIL = process.env.FULLSTACK_EMAIL ?? '';
const PASSWORD = process.env.FULLSTACK_PASSWORD ?? '';

interface Asset {
  id: string;
  role: string;
  status: string;
  mime: string;
  bytes: number;
  durationMs: number | null;
}
interface MemoryJson {
  id: string;
  kind: 'photo' | 'motion';
  assets: Asset[];
}

async function apiSignIn(
  request: APIRequestContext,
  email: string,
  password: string,
): Promise<string> {
  const response = await request.post(`${API}/v1/auth/sign-in/email`, {
    headers: { origin: ORIGIN },
    data: { email, password },
  });
  expect(response.ok(), `sign-in ${String(response.status())}`).toBe(true);
  return response.headers()['set-auth-token'] as string;
}

async function webSignIn(page: Page, email: string, password: string): Promise<void> {
  await page.goto('/sign-in');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Your library' })).toBeVisible();
}

/** A second account, created through the real sign-up and the mailed verification link. */
async function createSecondUser(request: APIRequestContext) {
  const email = `friend-${randomUUID().slice(0, 8)}@example.test`;
  const password = 'fullstack-friend-password';
  const signUp = await request.post(`${API}/v1/auth/sign-up/email`, {
    headers: { origin: ORIGIN },
    data: { name: 'Frankie', email, password },
  });
  expect(signUp.ok()).toBe(true);
  let link = '';
  await expect
    .poll(async () => {
      const outbox = (await (await request.get(`${API}/__test/outbox`)).json()) as {
        items: Array<{ kind: string; to: string; link: string }>;
      };
      link =
        outbox.items.filter((m) => m.kind === 'verify_email' && m.to === email).at(-1)?.link ?? '';
      return link !== '';
    })
    .toBe(true);
  expect((await request.get(link, { maxRedirects: 0 })).status()).toBeLessThan(400);
  return { email, password };
}

interface Box {
  type: string;
  payload: number;
  end: number;
}

/** The ISO base media boxes directly inside [from, to) of an MP4; they must tile the range exactly. */
function boxes(buffer: Buffer, from = 0, to = buffer.length): Box[] {
  const found: Box[] = [];
  let offset = from;
  while (offset + 8 <= to) {
    let size = buffer.readUInt32BE(offset);
    const type = buffer.subarray(offset + 4, offset + 8).toString('latin1');
    let header = 8;
    if (size === 1) {
      size = Number(buffer.readBigUInt64BE(offset + 8));
      header = 16;
    } else if (size === 0) {
      size = to - offset;
    }
    expect(size, `box ${type} at ${String(offset)} has a valid size`).toBeGreaterThanOrEqual(
      header,
    );
    found.push({ type, payload: offset + header, end: offset + size });
    offset += size;
  }
  expect(offset, 'boxes tile the file exactly').toBe(to);
  return found;
}

const child = (buffer: Buffer, parent: Box, type: string): Box | undefined =>
  boxes(buffer, parent.payload, parent.end).find((b) => b.type === type);

/** What a player needs from an MP4: duration, and the handler and sample-entry type of every track. */
function inspectMp4(buffer: Buffer) {
  const top = boxes(buffer);
  expect(top[0]?.type).toBe('ftyp');
  const moov = top.find((b) => b.type === 'moov');
  expect(moov, 'moov box').toBeDefined();
  expect(
    top.some((b) => b.type === 'mdat'),
    'mdat box',
  ).toBe(true);
  const mvhd = child(buffer, moov as Box, 'mvhd') as Box;
  const version = buffer.readUInt8(mvhd.payload);
  const timescale = buffer.readUInt32BE(mvhd.payload + (version === 1 ? 20 : 12));
  const duration =
    version === 1
      ? Number(buffer.readBigUInt64BE(mvhd.payload + 24))
      : buffer.readUInt32BE(mvhd.payload + 16);
  const tracks = boxes(buffer, (moov as Box).payload, (moov as Box).end)
    .filter((b) => b.type === 'trak')
    .map((trak) => {
      const mdia = child(buffer, trak, 'mdia') as Box;
      const hdlr = child(buffer, mdia, 'hdlr') as Box;
      const handler = buffer.subarray(hdlr.payload + 8, hdlr.payload + 12).toString('latin1');
      const minf = child(buffer, mdia, 'minf') as Box;
      const stbl = child(buffer, minf, 'stbl') as Box;
      const stsd = child(buffer, stbl, 'stsd') as Box;
      const codec = buffer.subarray(stsd.payload + 12, stsd.payload + 16).toString('latin1');
      return { handler, codec };
    });
  return { seconds: duration / timescale, tracks };
}

test.describe.configure({ mode: 'serial' });

test.describe('what the phone backed up shows up on the web', () => {
  test.skip(EMAIL === '', 'run through scripts/e2e-fullstack.sh');

  let memories: MemoryJson[] = [];
  let token = '';

  test('[WEB-001][WEB-002][MEM-001][MOT-005][SYNC-008] the app account signs in and sees both captured Memories, fully verified', async ({
    page,
    request,
  }) => {
    token = await apiSignIn(request, EMAIL, PASSWORD);
    await webSignIn(page, EMAIL, PASSWORD);
    const tiles = page.getByRole('list', { name: 'Memories' }).getByRole('link');
    await expect(tiles).toHaveCount(2);
    await expect(tiles.getByText('LIVE')).toHaveCount(1);
    await expect(page.getByText(/^Storage: .* of 10 GB used$/)).toBeVisible();
    // both thumbnails really load from storage
    for (const index of [0, 1]) {
      await expect
        .poll(() =>
          tiles
            .nth(index)
            .getByRole('img')
            .evaluate((img: HTMLImageElement) => img.naturalWidth),
        )
        .toBeGreaterThan(0);
    }

    const list = await request.get(`${API}/v1/memories`, {
      headers: { authorization: `Bearer ${token}` },
    });
    memories = ((await list.json()) as { items: MemoryJson[] }).items;
    expect(memories.map((m) => m.kind).sort()).toEqual(['motion', 'photo']);
    for (const memory of memories) {
      for (const asset of memory.assets) {
        expect(['verified', 'ready'], `${memory.kind} ${asset.role}`).toContain(asset.status);
        expect(asset.bytes).toBeGreaterThan(0);
      }
    }
    const photo = memories.find((m) => m.kind === 'photo') as MemoryJson;
    expect(photo.assets.map((a) => a.role)).toEqual(
      expect.arrayContaining(['photo_original', 'thumbnail']),
    );
    const motion = memories.find((m) => m.kind === 'motion') as MemoryJson;
    expect(motion.assets.map((a) => a.role)).toEqual(
      expect.arrayContaining(['photo_original', 'motion_clip']),
    );
  });

  test('[WEB-003][WEB-004][SYNC-008] the original photo is a complete JPEG of the size the app reported', async ({
    page,
    request,
  }) => {
    const photo = memories.find((m) => m.kind === 'photo') as MemoryJson;
    const original = photo.assets.find((a) => a.role === 'photo_original') as Asset;
    const link = await request.get(
      `${API}/v1/memories/${photo.id}/assets/${original.id}/download`,
      { headers: { authorization: `Bearer ${token}` } },
    );
    const url = ((await link.json()) as { url: string }).url;
    const bytes = await (await request.get(url.startsWith('/') ? `${API}${url}` : url)).body();
    expect(bytes.length).toBe(original.bytes);
    expect(bytes.subarray(0, 3).toString('hex')).toBe('ffd8ff');
    expect(bytes.subarray(-2).toString('hex')).toBe('ffd9');
    // the dashboard's own detail page offers it
    await webSignIn(page, EMAIL, PASSWORD);
    await page.goto(`/memories/${photo.id}`);
    await expect(page.locator('dl.meta')).toBeVisible();
    await expect(page.getByRole('button', { name: /Download original/ })).toBeVisible();
  });

  test('[MOT-004][MOT-006][MOT-002] the motion memory plays in the browser and its clip is a real MP4 with video and sound', async ({
    page,
    request,
    browserName,
  }) => {
    const motion = memories.find((m) => m.kind === 'motion') as MemoryJson;
    await webSignIn(page, EMAIL, PASSWORD);
    await page.goto(`/memories/${motion.id}`);
    await expect(page.getByText(/Motion Memory/)).toBeVisible();
    await page.getByRole('button', { name: 'Play motion' }).click();
    const video = page.getByLabel('Motion playback');
    await expect(video).toBeVisible();
    const src = (await video.getAttribute('src')) as string;
    const bytes = await (await request.get(src)).body();

    // byte level: a complete, well-formed MP4 with an H.264 video track and an AAC audio track
    const mp4 = inspectMp4(bytes);
    expect(mp4.seconds).toBeGreaterThan(0.5);
    expect(mp4.tracks).toEqual(
      expect.arrayContaining([
        { handler: 'vide', codec: 'avc1' },
        { handler: 'soun', codec: 'mp4a' },
      ]),
    );
    const served =
      motion.assets.find((a) => a.role === 'motion_web') ??
      motion.assets.find((a) => a.role === 'motion_clip');
    expect(bytes.length).toBe((served as Asset).bytes);

    const canH264 = await page.evaluate(
      () =>
        document.createElement('video').canPlayType('video/mp4; codecs="avc1.42E01E, mp4a.40.2"') !==
        '',
    );
    test.skip(!canH264, `${browserName} here has no H.264 decoder; the bytes were verified above`);
    await expect
      .poll(() => video.evaluate((v: HTMLVideoElement) => v.readyState))
      .toBeGreaterThanOrEqual(2);
    expect(await video.evaluate((v: HTMLVideoElement) => v.duration)).toBeGreaterThan(0.5);
    await video.evaluate((v: HTMLVideoElement) => {
      v.currentTime = Math.max(0, v.duration - 0.05);
    });
    await expect(page.getByRole('button', { name: 'Play motion' })).toBeVisible({
      timeout: 15_000,
    });
  });

  test('[SHR-001][SHR-003][WEB-007] the owner makes an album, invites a second account, who sees the shared Memories', async ({
    browser,
    request,
  }) => {
    const friend = await createSecondUser(request);
    const ownerCtx = await browser.newContext();
    const owner = await ownerCtx.newPage();
    await webSignIn(owner, EMAIL, PASSWORD);
    await owner.getByRole('link', { name: 'Albums' }).click();
    await owner.getByLabel('Title').fill('Full-stack trip');
    await owner.getByRole('button', { name: 'Create album' }).click();
    await expect(owner.getByRole('heading', { level: 1, name: 'Full-stack trip' })).toBeVisible();

    const picker = owner.getByRole('list', { name: 'Your memories to add' });
    await expect(picker.getByRole('checkbox')).toHaveCount(2);
    await picker.getByRole('checkbox').nth(0).check();
    await picker.getByRole('checkbox').nth(1).check();
    await owner.getByRole('button', { name: /Add selected/ }).click();
    await expect(owner.getByRole('heading', { name: 'Remove from album' })).toBeVisible();

    await owner.getByLabel('Role', { exact: true }).selectOption('viewer');
    await owner.getByRole('button', { name: 'Create invite link' }).click();
    const linkText = await owner.getByText(/Share this link/).textContent();
    const inviteUrl = /(http:\/\/\S+\/invites\/\S+)/.exec(linkText ?? '')?.[1] as string;
    expect(inviteUrl).toContain('/invites/');

    const friendCtx = await browser.newContext();
    const guest = await friendCtx.newPage();
    await webSignIn(guest, friend.email, friend.password);
    await guest.goto(new URL(inviteUrl).pathname);
    await guest.getByRole('button', { name: 'Accept invite' }).click();
    await expect(guest.getByRole('heading', { level: 1, name: 'Full-stack trip' })).toBeVisible();
    await expect(guest.getByText('You are a viewer.')).toBeVisible();
    await expect(guest.getByRole('main').getByRole('img')).toHaveCount(2);
    await expect(guest.getByRole('heading', { name: 'Add your memories' })).toHaveCount(0);
    await expect(guest.getByRole('heading', { name: 'Invite someone' })).toHaveCount(0);

    // the friend opens the motion memory and the clip is served to them too
    const motion = memories.find((m) => m.kind === 'motion') as MemoryJson;
    await guest.goto(`/memories/${motion.id}`);
    await expect(guest.getByText(/Motion Memory/)).toBeVisible();
    await guest.getByRole('button', { name: 'Play motion' }).click();
    const src = (await guest.getByLabel('Motion playback').getAttribute('src')) as string;
    const bytes = await (await friendCtx.request.get(src)).body();
    expect(bytes.subarray(4, 8).toString('latin1')).toBe('ftyp');
    await Promise.all([ownerCtx.close(), friendCtx.close()]);
  });
});

test.describe('what the web changes comes back to the phone', () => {
  test.skip(EMAIL === '', 'run through scripts/e2e-fullstack.sh');

  test('[WEB-003][MEM-004][MEM-006] a caption and favorite set in the dashboard are stored for the phone to pull', async ({
    page,
    request,
  }) => {
    const token = await apiSignIn(request, EMAIL, PASSWORD);
    const list = await request.get(`${API}/v1/memories`, {
      headers: { authorization: `Bearer ${token}` },
    });
    const photo = ((await list.json()) as { items: MemoryJson[] }).items.find(
      (m) => m.kind === 'photo',
    ) as MemoryJson;
    await webSignIn(page, EMAIL, PASSWORD);
    await page.goto(`/memories/${photo.id}`);
    await page.getByLabel('Caption').fill('Caption written on the web');
    await page.getByRole('button', { name: 'Save caption' }).click();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Caption written on the web' }),
    ).toBeVisible();
    await page.getByRole('button', { name: '☆ Favorite' }).click();
    await expect(page.getByRole('button', { name: '★ Favorite' })).toBeVisible();
  });
});
