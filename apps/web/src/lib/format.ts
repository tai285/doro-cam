const UNITS = ['B', 'KB', 'MB', 'GB', 'TB'] as const;

/** 1536 → "1.5 KB". Uses 1024-based units, matching how storage quotas are counted. */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) {
    return '—';
  }
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024;
    unit += 1;
  }
  const digits = unit === 0 || value >= 100 ? 0 : value >= 10 ? 1 : 2;
  return `${String(Number(value.toFixed(digits)))} ${UNITS[unit] ?? 'B'}`;
}

/** The moment a photo was taken, shown in the time zone it was shot in ("shot at 21:00 local"). */
export function formatCaptured(iso: string, timeZone: string): string {
  const date = new Date(iso);
  try {
    return new Intl.DateTimeFormat('en-GB', {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone,
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat('en-GB', {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: 'UTC',
    }).format(date);
  }
}

export function formatDate(iso: string): string {
  return new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium' }).format(new Date(iso));
}

/** 8_000_000 ns → "1/125 s"; 2_000_000_000 ns → "2 s". */
export function formatShutter(exposureNs: number): string {
  const seconds = exposureNs / 1e9;
  if (seconds >= 1) {
    return `${String(Number(seconds.toFixed(1)))} s`;
  }
  return `1/${String(Math.round(1 / seconds))} s`;
}

export function percent(share: number): string {
  return `${String(Math.round(share * 100))}%`;
}

export function usedShare(used: number, quota: number): number {
  return quota <= 0 ? 0 : Math.min(1, used / quota);
}

export function memoryLabel(memory: {
  caption: string | null;
  capturedAt: string;
  capturedTz: string;
  kind: string;
}): string {
  if (memory.caption !== null && memory.caption.trim() !== '') {
    return memory.caption;
  }
  const noun =
    memory.kind === 'motion' ? 'Motion memory' : memory.kind === 'video' ? 'Video' : 'Photo';
  return `${noun} from ${formatCaptured(memory.capturedAt, memory.capturedTz)}`;
}
