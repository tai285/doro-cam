import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { MediaError, extractPoster, probe, stripMetadata, transcodeToWebMp4 } from '../src/modules/media/ffmpeg.ts';
import { makeVideo } from './helpers/video.ts';

const run = promisify(execFile);

describe('ffmpeg wrapper failure and edge paths', () => {
  let dir: string;
  let clip: string;
  let garbage: string;

  beforeAll(async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), 'doro-ffmpeg-'));
    clip = path.join(dir, 'clip.mp4');
    await writeFile(clip, await makeVideo());
    garbage = path.join(dir, 'garbage.mp4');
    await writeFile(garbage, Buffer.from('this is not a media file at all'));
  });
  afterAll(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('probe throws MediaError for a file ffprobe cannot parse and for a missing file', async () => {
    await expect(probe(garbage)).rejects.toBeInstanceOf(MediaError);
    await expect(probe(path.join(dir, 'missing.mp4'))).rejects.toThrow('ffprobe could not read the file');
  });

  it('probe reports no duration for a raw elementary stream that has none', async () => {
    const raw = path.join(dir, 'raw.h264');
    await run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', clip, '-an', '-c:v', 'copy', '-f', 'h264', raw]);
    const info = await probe(raw);
    expect(info.hasVideo).toBe(true);
    expect(info.hasAudio).toBe(false);
    expect(info.width).toBeGreaterThan(0);
    expect(info.durationMs === null || info.durationMs >= 0).toBe(true);
  });

  it('every operation wraps an ffmpeg failure in a MediaError that says what ffmpeg reported', async () => {
    for (const operation of [
      () => transcodeToWebMp4(garbage, path.join(dir, 'o1.mp4')),
      () => extractPoster(garbage, path.join(dir, 'o2.jpg'), 0),
      () => stripMetadata(garbage, path.join(dir, 'o3.mp4')),
    ]) {
      const error = await operation().then(
        () => undefined,
        (caught: unknown) => caught,
      );
      expect(error).toBeInstanceOf(MediaError);
      expect((error as MediaError).message).toMatch(/^ffmpeg failed: /);
      expect((error as MediaError).cause).toBeDefined();
    }
  });

  it('a negative poster time is clamped to the first frame', async () => {
    const poster = path.join(dir, 'poster.jpg');
    await extractPoster(clip, poster, -5, 64);
    const bytes = await readFile(poster);
    expect(bytes.subarray(0, 2).toString('hex')).toBe('ffd8');
    expect((await stat(poster)).size).toBeGreaterThan(100);
  });
});
