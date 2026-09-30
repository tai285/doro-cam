import Fastify, { type FastifyInstance, type FastifyPluginAsync } from 'fastify';
import { serializerCompiler, validatorCompiler } from 'fastify-type-provider-zod';
import type { AppConfig } from './config/env.ts';
import type { Database } from './db/client.ts';
import { registerErrorHandling } from './lib/error-handler.ts';
import { REQUEST_ID_HEADER, resolveRequestId } from './lib/request-id.ts';
import type { Storage } from './lib/storage.ts';
import { healthRoutes } from './modules/health/routes.ts';

export interface AppDeps {
  config: AppConfig;
  database: Database;
  storage: Storage;
}

export interface BuildAppOptions {
  /** Feature modules (auth, memories, ...) register here. Each is a Fastify plugin owned by its module. */
  modules?: readonly FastifyPluginAsync[];
  /** Destination for log lines. Defaults to stdout; tests capture it to assert on what gets logged. */
  logStream?: NodeJS.WritableStream;
}

/**
 * Builds the Fastify instance without listening, so the server, the tests and later the
 * OpenAPI generator all use exactly the same app (docs/architecture/backend.md).
 */
export async function buildApp(deps: AppDeps, options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: deps.config.logLevel,
      // Never write credentials or session tokens to logs (NFR-011).
      redact: ['req.headers.authorization', 'req.headers.cookie', 'res.headers["set-cookie"]'],
      ...(options.logStream === undefined ? {} : { stream: options.logStream }),
    },
    genReqId: (request) => resolveRequestId(request.headers[REQUEST_ID_HEADER]),
    requestIdHeader: false,
    // Uploads never pass through the API (ADR-0008), so request bodies stay small.
    bodyLimit: 1024 * 1024,
  });

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);
  app.addHook('onSend', async (request, reply) => {
    void reply.header(REQUEST_ID_HEADER, request.id);
  });
  registerErrorHandling(app);

  await app.register(
    healthRoutes([
      { name: 'database', run: () => deps.database.check() },
      { name: 'storage', run: () => deps.storage.checkBucket() },
    ]),
  );
  for (const module of options.modules ?? []) {
    await app.register(module);
  }
  return app;
}
