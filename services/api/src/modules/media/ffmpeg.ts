import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);

/** ffmpeg binaries are resolved from PATH; override for odd installs. */
const FFMPEG = process.env.FFMPEG_PATH ?? 'ffmpeg';
const FFPROBE = process.env.FFPROBE_PATH ?? 'ffprobe';
const TIMEOUT_MS = 10 * 60_000;

export class MediaError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'MediaError';
  }
}

export interface MediaInfo {
  durationMs: number | null;
  width: number | null;
  height: number | null;
  hasAudio: boolean;
  hasVideo: boolean;
}

async function ffmpeg(args: string[]): Promise<void> {
  try {
    await run(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-y', ...args], { timeout: TIMEOUT_MS, maxBuffer: 1024 * 1024 });
  } catch (error) {
    throw new MediaError(`ffmpeg failed: ${(error as { stderr?: string }).stderr?.slice(0, 300) ?? String(error)}`, { cause: error });
  }
}

/** Reads container facts with ffprobe. Throws MediaError for files ffprobe cannot parse. */
export async function probe(file: string): Promise<MediaInfo> {
  try {
    const { stdout } = await run(FFPROBE, ['-v', 'error', '-print_format', 'json', '-show_streams', '-show_format', file], { timeout: 60_000, maxBuffer: 4 * 1024 * 1024 });
    const parsed = JSON.parse(stdout) as {
      streams?: Array<{ codec_type?: string; width?: number; height?: number; duration?: string }>;
      format?: { duration?: string };
    };
    const video = parsed.streams?.find((stream) => stream.codec_type === 'video');
    const seconds = Number(parsed.format?.duration ?? video?.duration ?? Number.NaN);
    return {
      durationMs: Number.isFinite(seconds) ? Math.round(seconds * 1000) : null,
      width: video?.width ?? null,
      height: video?.height ?? null,
      hasAudio: parsed.streams?.some((stream) => stream.codec_type === 'audio') ?? false,
      hasVideo: video !== undefined,
    };
  } catch (error) {
    throw new MediaError('ffprobe could not read the file', { cause: error });
  }
}

/** H.264 + AAC in a fast-start MP4 that every browser plays (media-pipeline "motion_web" / "video_web"). Audio is optional. */
export async function transcodeToWebMp4(input: string, output: string): Promise<void> {
  await ffmpeg([
    '-i', input,
    '-map', '0:v:0', '-map', '0:a:0?',
    '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '128k',
    '-movflags', '+faststart',
    '-map_metadata', '-1',
    output,
  ]);
}

/** One JPEG frame at `seconds`, at most `longEdge` pixels on the long side. */
export async function extractPoster(input: string, output: string, seconds: number, longEdge = 2048): Promise<void> {
  await ffmpeg([
    '-ss', String(Math.max(0, seconds)),
    '-i', input,
    '-frames:v', '1',
    '-vf', `scale='if(gt(iw,ih),min(${String(longEdge)},iw),-2)':'if(gt(iw,ih),-2,min(${String(longEdge)},ih))'`,
    '-q:v', '3',
    output,
  ]);
}

/** Copies the streams without any container metadata (location atoms, creation time, device tags) — PRIV-002. */
export async function stripMetadata(input: string, output: string): Promise<void> {
  await ffmpeg(['-i', input, '-map', '0', '-c', 'copy', '-map_metadata', '-1', '-map_chapters', '-1', '-movflags', '+faststart', '-f', 'mp4', output]);
}
