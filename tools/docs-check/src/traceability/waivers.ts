export interface Waiver {
  requirement: string;
  reason: string;
  /** 1-based position in the waiver file, used in error messages. */
  index: number;
}

export interface ParsedWaivers {
  waivers: Waiver[];
  /** Problems with the file itself. Invalid entries are reported and left out of `waivers`. */
  errors: string[];
}

const REQUIREMENT_ID_RE = /^[A-Z][A-Z0-9]*-\d{3}$/;

/**
 * Parses docs/product/traceability-waivers.json: requirements that cannot be proven by a test
 * (process requirements, meta requirements) and the reason why. Waivers without a reason do not count.
 */
export function parseWaivers(text: string): ParsedWaivers {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch (error) {
    return { waivers: [], errors: [`is not valid JSON: ${error instanceof Error ? error.message : String(error)}`] };
  }
  if (!Array.isArray(data)) {
    return { waivers: [], errors: ['must contain a JSON array of { "requirement", "reason" } objects'] };
  }

  const waivers: Waiver[] = [];
  const errors: string[] = [];
  const firstIndexOf = new Map<string, number>();

  (data as unknown[]).forEach((entry, position) => {
    const index = position + 1;
    if (typeof entry !== 'object' || entry === null || Array.isArray(entry)) {
      errors.push(`waiver ${index} must be an object`);
      return;
    }
    const { requirement, reason } = entry as { requirement?: unknown; reason?: unknown };
    if (typeof requirement !== 'string' || !REQUIREMENT_ID_RE.test(requirement)) {
      errors.push(`waiver ${index} needs a "requirement" ID`);
      return;
    }
    if (typeof reason !== 'string' || reason.trim() === '') {
      errors.push(`waiver ${index} (${requirement}) needs a non-empty reason`);
      return;
    }
    const first = firstIndexOf.get(requirement);
    if (first !== undefined) {
      errors.push(`waiver ${index} (${requirement}) duplicates waiver ${first}`);
      return;
    }
    firstIndexOf.set(requirement, index);
    waivers.push({ requirement, reason: reason.trim(), index });
  });
  return { waivers, errors };
}
