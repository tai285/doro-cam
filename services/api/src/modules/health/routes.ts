import type { FastifyPluginAsync } from 'fastify';
import { type ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { withTimeout } from '../../lib/timeout.ts';

export type CheckName = 'database' | 'storage';

export interface ReadinessCheck {
  name: CheckName;
  run(): Promise<void>;
}

const CHECK_TIMEOUT_MS = 3000;

const livenessSchema = z.object({ status: z.literal('ok') });
const readinessSchema = z.object({
  status: z.enum(['ready', 'unavailable']),
  checks: z.partialRecord(z.enum(['database', 'storage']), z.enum(['ok', 'fail'])),
});

/**
 * GET /healthz: the process is up (used by the orchestrator to decide whether to restart it).
 * GET /readyz:  dependencies are reachable (used to decide whether to send it traffic).
 * Both are unauthenticated and reveal only pass/fail per dependency, never error details.
 */
export function healthRoutes(checks: readonly ReadinessCheck[]): FastifyPluginAsync {
  return async (app) => {
    const typed = app.withTypeProvider<ZodTypeProvider>();

    typed.get('/healthz', { schema: { response: { 200: livenessSchema } } }, async () => ({ status: 'ok' as const }));

    typed.get(
      '/readyz',
      { schema: { response: { 200: readinessSchema, 503: readinessSchema } } },
      async (request, reply) => {
        const results = await Promise.all(
          checks.map(async (check) => {
            try {
              await withTimeout(check.run(), CHECK_TIMEOUT_MS, `${check.name} check`);
              return [check.name, 'ok' as const] as const;
            } catch (error) {
              request.log.warn({ err: error, check: check.name }, 'readiness check failed');
              return [check.name, 'fail' as const] as const;
            }
          }),
        );
        const allOk = results.every(([, state]) => state === 'ok');
        return reply.status(allOk ? 200 : 503).send({
          status: allOk ? 'ready' : 'unavailable',
          checks: Object.fromEntries(results) as Partial<Record<CheckName, 'ok' | 'fail'>>,
        });
      },
    );
  };
}
