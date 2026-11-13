/** API shapes used by the dashboard. They mirror packages/api-contract/openapi.json (docs/specs/api.md). */

export type MemoryKind = 'photo' | 'motion' | 'video';
export type AssetRole =
  | 'photo_original'
  | 'photo_rendered'
  | 'photo_display'
  | 'thumbnail'
  | 'motion_clip'
  | 'motion_web'
  | 'video_original'
  | 'video_web'
  | 'video_poster'
  | 'sanitized_original';
export type AssetStatus = 'pending' | 'uploading' | 'uploaded' | 'verified' | 'ready' | 'failed';
export type AlbumRole = 'owner' | 'editor' | 'contributor' | 'viewer';

export interface MediaUrl {
  url: string;
  expiresAt: string;
}

export interface AssetSummary {
  id: string;
  role: AssetRole;
  status: AssetStatus;
  mime: string;
  bytes: number;
  width: number | null;
  height: number | null;
  durationMs: number | null;
  failureReason: string | null;
}

export interface Memory {
  id: string;
  ownerId: string;
  isOwner: boolean;
  kind: MemoryKind;
  capturedAt: string;
  capturedTz: string;
  experienceId: string;
  profile: { id: string; version: number } | null;
  presetId: string | null;
  scenario: string | null;
  capture: Record<string, unknown>;
  location: { lat: number; lon: number; accuracyM: number | null } | null;
  locationShared?: boolean;
  caption: string | null;
  favorite: boolean;
  aspectRatio: string | null;
  version: number;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  assets: AssetSummary[];
  thumbnail: MediaUrl | null;
  display: MediaUrl | null;
}

export interface MemoryPage {
  items: Memory[];
  nextCursor: string | null;
}

export interface Me {
  id: string;
  email: string;
  name: string;
  emailVerified: boolean;
  createdAt: string;
  storage: { usedBytes: number; quotaBytes: number };
  deletionRequestedAt: string | null;
  deletionScheduledFor: string | null;
}

export interface DeviceSession {
  id: string;
  current: boolean;
  userAgent: string | null;
  ipAddress: string | null;
  createdAt: string;
  expiresAt: string;
}

export interface Album {
  id: string;
  ownerId: string;
  kind: 'album' | 'trip';
  title: string;
  description: string | null;
  startsOn: string | null;
  endsOn: string | null;
  coverMemoryId: string | null;
  allowOriginalDownload: boolean;
  shareLocation: boolean;
  autoAddDuringTrip: boolean;
  role: AlbumRole;
  memberCount: number;
  itemCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface AlbumMember {
  userId: string;
  name: string;
  role: AlbumRole;
  joinedAt: string;
}

export interface Preset {
  id: string;
  name: string;
  experienceId: string;
  intent: Record<string, unknown>;
  profile: { id: string; version: number } | null;
  live: boolean;
  source: 'user' | 'suggested';
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface Bucket {
  label: string;
  count: number;
  share: number;
}
export interface Distribution {
  total: number;
  buckets: Bucket[];
}
export interface InsightsReport {
  total: number;
  focalLength: Distribution;
  lens: Distribution;
  profile: Distribution;
  experience: Distribution;
  iso: Distribution;
  shutter: Distribution;
  aperture: Distribution;
  timeOfDay: Distribution;
  trend: Array<{ month: string; count: number }>;
  insights: Array<{ id: string; text: string; basedOn: Record<string, number | string> }>;
}

export interface PresetSuggestion {
  patternKey: string;
  title: string;
  explanation: string;
  experienceId: string;
  profileId: string | null;
  scenario: string | null;
  lensKind: string | null;
  isoRange: string | null;
  shutterRange: string | null;
  supportingCount: number;
  of: number;
  share: number;
}

export interface DownloadLink {
  url: string;
  expiresAt: string;
  sanitized: boolean;
  filename: string;
}

export interface DataExport {
  id: string;
  status: 'pending' | 'building' | 'ready' | 'failed';
  bytes: number | null;
  createdAt: string;
  completedAt: string | null;
  expiresAt: string;
  failureReason: string | null;
  download: { url: string; expiresAt: string; filename: string } | null;
}

export interface PublicConfig {
  socialProviders: Array<'google' | 'apple'>;
  emailPassword: true;
}
