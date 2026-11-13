import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';

const run = promisify(execFile);

/** A real (tiny) clip made by ffmpeg, optionally with a GPS location tag and an audio track. */
export async function makeVideo(options: { seconds?: number; audio?: boolean; location?: string; container?: 'mp4' | 'mov' } = {}): Promise<Buffer> {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-test-video-'));
  try {
    const file = path.join(dir, `clip.${options.container ?? 'mp4'}`);
    const seconds = String(options.seconds ?? 2);
    const args = ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', `testsrc=duration=${seconds}:size=320x240:rate=15`];
    if (options.audio !== false) {
      args.push('-f', 'lavfi', '-i', `sine=frequency=440:duration=${seconds}`);
    }
    args.push('-c:v', 'libx264', '-pix_fmt', 'yuv420p');
    if (options.audio !== false) {
      args.push('-c:a', 'aac');
    }
    if (options.location !== undefined) {
      args.push('-metadata', `location=${options.location}`, '-metadata', `com.apple.quicktime.location.ISO6709=${options.location}`);
    }
    args.push(file);
    await run('ffmpeg', args);
    return await readFile(file);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

/** ffprobe JSON for a buffer (streams and format tags). */
export async function probeBuffer(data: Buffer): Promise<{ streams: Array<{ codec_name?: string; codec_type?: string }>; format: { tags?: Record<string, string>; duration?: string } }> {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-test-probe-'));
  try {
    const file = path.join(dir, 'in.bin');
    await (await import('node:fs/promises')).writeFile(file, data);
    const { stdout } = await run('ffprobe', ['-v', 'error', '-print_format', 'json', '-show_streams', '-show_format', file]);
    return JSON.parse(stdout) as { streams: Array<{ codec_name?: string; codec_type?: string }>; format: { tags?: Record<string, string>; duration?: string } };
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}
