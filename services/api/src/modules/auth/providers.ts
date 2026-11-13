import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import type { AppConfig } from '../../config/env.ts';

/**
 * Public, unauthenticated description of how people may sign in. Clients read it to decide whether to
 * show "Continue with Google/Apple" (AUTH-002, AUTH-003). Reveals only provider names, never credentials.
 */
export function authConfigRoutes(config: AppConfig): FastifyPluginAsync {
  return async (app) => {
    app.withTypeProvider<ZodTypeProvider>().get(
      '/v1/config',
      { schema: { response: { 200: z.object({ socialProviders: z.array(z.enum(['google', 'apple'])), emailPassword: z.literal(true) }) } } },
      async () => ({
        socialProviders: [...(config.auth.social.google === undefined ? [] : (['google'] as const)), ...(config.auth.social.apple === undefined ? [] : (['apple'] as const))],
        emailPassword: true as const,
      }),
    );
  };
}
