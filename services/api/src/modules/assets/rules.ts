export const MIB = 1024 * 1024;
export const SINGLE_UPLOAD_MAX_BYTES = 16 * MIB;
const MIN_PART_BYTES = 8 * MIB;
const MAX_PARTS = 10_000;

export type ClientRole = 'photo_original' | 'photo_rendered' | 'photo_display' | 'thumbnail' | 'motion_clip' | 'video_original';
export type MemoryKind = 'photo' | 'motion' | 'video';

interface RoleRule {
  mimes: readonly string[];
  maxBytes: number;
  kinds: readonly MemoryKind[];
}

/** What each client-uploaded role may contain (docs/architecture/media-pipeline.md). */
export const ROLE_RULES: Record<ClientRole, RoleRule> = {
  photo_original: {
    mimes: ['image/jpeg', 'image/heic', 'image/heif', 'image/x-adobe-dng'],
    maxBytes: 200 * MIB,
    kinds: ['photo', 'motion'],
  },
  photo_rendered: { mimes: ['image/jpeg'], maxBytes: 100 * MIB, kinds: ['photo', 'motion'] },
  photo_display: { mimes: ['image/jpeg'], maxBytes: 20 * MIB, kinds: ['photo', 'motion'] },
  thumbnail: { mimes: ['image/jpeg'], maxBytes: 5 * MIB, kinds: ['photo', 'motion', 'video'] },
  motion_clip: { mimes: ['video/mp4', 'video/quicktime'], maxBytes: 2048 * MIB, kinds: ['motion'] },
  video_original: { mimes: ['video/mp4', 'video/quicktime'], maxBytes: 4096 * MIB, kinds: ['video'] },
};

export type UploadCheck = { ok: true } | { ok: false; code: 'role_not_allowed' | 'unsupported_type' | 'too_large' };

export function checkUpload(role: ClientRole, kind: MemoryKind, mime: string, bytes: number): UploadCheck {
  const rule = ROLE_RULES[role];
  if (!rule.kinds.includes(kind)) {
    return { ok: false, code: 'role_not_allowed' };
  }
  if (!rule.mimes.includes(mime)) {
    return { ok: false, code: 'unsupported_type' };
  }
  if (bytes > rule.maxBytes) {
    return { ok: false, code: 'too_large' };
  }
  return { ok: true };
}

export type UploadPlan = { mode: 'single' } | { mode: 'multipart'; partSize: number; partCount: number };

/** Single PUT up to 16 MiB; otherwise multipart with part size max(8 MiB, ceil(bytes / 10000)) rounded up to a whole MiB. */
export function planUpload(bytes: number): UploadPlan {
  if (bytes <= SINGLE_UPLOAD_MAX_BYTES) {
    return { mode: 'single' };
  }
  const minimum = Math.max(MIN_PART_BYTES, Math.ceil(bytes / MAX_PARTS));
  const partSize = Math.ceil(minimum / MIB) * MIB;
  return { mode: 'multipart', partSize, partCount: Math.ceil(bytes / partSize) };
}
