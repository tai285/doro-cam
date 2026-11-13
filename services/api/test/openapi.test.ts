import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { generateOpenApi } from '../src/openapi.ts';

const committed = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'packages', 'api-contract', 'openapi.json');

describe('OpenAPI contract', () => {
  it('[NFR-014] the committed contract matches the routes (run `pnpm --filter @doro/api openapi` after changing an endpoint)', async () => {
    expect(readFileSync(committed, 'utf8')).toBe(await generateOpenApi());
  });

  it('documents every public route group with bodies and responses', async () => {
    const spec = JSON.parse(await generateOpenApi()) as { paths: Record<string, Record<string, { responses?: Record<string, unknown> }>> };
    const paths = Object.keys(spec.paths);
    for (const prefix of ['/v1/me', '/v1/memories', '/v1/albums', '/v1/presets', '/v1/sync', '/v1/insights', '/v1/invites', '/healthz']) {
      expect(paths.some((p) => p.startsWith(prefix)), prefix).toBe(true);
    }
    const upload = spec.paths['/v1/memories/{memoryId}/assets/{assetId}/upload']?.post;
    expect(upload?.responses?.['200']).toBeDefined();
  });
});
