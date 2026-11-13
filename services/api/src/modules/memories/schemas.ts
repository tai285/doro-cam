import { z } from 'zod';

export const memoryKindSchema = z.enum(['photo', 'motion', 'video']);
export const lensKindSchema = z.enum(['ultraWide', 'wide', 'tele', 'front', 'other']);
export const assetRoleSchema = z.enum([
  'photo_original',
  'photo_rendered',
  'photo_display',
  'thumbnail',
  'motion_clip',
  'motion_web',
  'video_original',
  'video_web',
  'video_poster',
  'sanitized_original',
]);
export const assetStatusSchema = z.enum(['pending', 'uploading', 'uploaded', 'verified', 'ready', 'failed']);

/** Roles a client may upload. Worker-generated roles (motion_web, sanitized_original) are never accepted from clients. */
export const clientAssetRoleSchema = z.enum([
  'photo_original',
  'photo_rendered',
  'photo_display',
  'thumbnail',
  'motion_clip',
  'video_original',
]);

/**
 * The settings actually applied by the device (CAM-050) plus a few typed fields the server extracts for
 * analytics (ADR-0007). Everything else the device reports is kept verbatim.
 */
export const captureMetadataSchema = z.looseObject({
  lensKind: lensKindSchema.optional(),
  focalLength35mmEq: z.number().positive().max(2000).optional(),
  aperture: z.number().positive().max(64).optional(),
  isoApplied: z.number().int().positive().max(10_000_000).optional(),
  exposureTimeNsApplied: z.number().int().positive().optional(),
});

export const locationSchema = z.object({
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
  accuracyM: z.number().nonnegative().optional(),
});

export const registerMemoryBody = z.object({
  kind: memoryKindSchema,
  capturedAt: z.iso.datetime({ offset: true }),
  capturedTz: z.string().min(1).max(64),
  experienceId: z.string().min(1).max(64),
  profile: z.object({ id: z.string().min(1).max(64), version: z.number().int().positive() }).optional(),
  presetId: z.uuid().optional(),
  scenario: z.string().min(1).max(64).optional(),
  capture: captureMetadataSchema,
  location: locationSchema.optional(),
  caption: z.string().max(2000).optional(),
  favorite: z.boolean().optional(),
  aspectRatio: z.string().regex(/^\d{1,2}:\d{1,2}$/).optional(),
});
export type RegisterMemoryBody = z.infer<typeof registerMemoryBody>;

export const patchMemoryBody = z
  .object({
    caption: z.string().max(2000).nullable().optional(),
    favorite: z.boolean().optional(),
    removeLocation: z.literal(true).optional(),
    locationShared: z.boolean().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, { message: 'at least one field is required' });

export const assetSummarySchema = z.object({
  id: z.string(),
  role: assetRoleSchema,
  status: assetStatusSchema,
  mime: z.string(),
  bytes: z.number(),
  width: z.number().nullable(),
  height: z.number().nullable(),
  durationMs: z.number().nullable(),
  failureReason: z.string().nullable(),
});

export const mediaUrlSchema = z.object({ url: z.string(), expiresAt: z.string() });

export const memorySchema = z.object({
  id: z.string(),
  ownerId: z.string(),
  isOwner: z.boolean(),
  kind: memoryKindSchema,
  capturedAt: z.string(),
  capturedTz: z.string(),
  experienceId: z.string(),
  profile: z.object({ id: z.string(), version: z.number() }).nullable(),
  presetId: z.string().nullable(),
  scenario: z.string().nullable(),
  capture: z.record(z.string(), z.unknown()),
  location: z.object({ lat: z.number(), lon: z.number(), accuracyM: z.number().nullable() }).nullable(),
  locationShared: z.boolean().optional(),
  caption: z.string().nullable(),
  favorite: z.boolean(),
  aspectRatio: z.string().nullable(),
  publicHandle: z.string().optional(),
  version: z.number(),
  createdAt: z.string(),
  updatedAt: z.string(),
  deletedAt: z.string().nullable(),
  assets: z.array(assetSummarySchema),
  thumbnail: mediaUrlSchema.nullable(),
  display: mediaUrlSchema.nullable(),
});
export type MemoryDto = z.infer<typeof memorySchema>;

export const listQuery = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(50),
  cursor: z.string().max(200).optional(),
  kind: memoryKindSchema.optional(),
  favorite: z
    .enum(['true', 'false'])
    .transform((value) => value === 'true')
    .optional(),
  trashed: z
    .enum(['true', 'false'])
    .transform((value) => value === 'true')
    .default(false),
});

export const memoryParams = z.object({ memoryId: z.uuid() });
