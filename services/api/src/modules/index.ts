import type { FastifyPluginAsync } from 'fastify';
import type { AppConfig } from '../config/env.ts';
import type { Database } from '../db/client.ts';
import type { Mailer } from '../lib/mailer.ts';
import type { JobQueue } from '../lib/queue.ts';
import type { Storage } from '../lib/storage.ts';
import { albumRoutes } from './albums/routes.ts';
import { assetRoutes } from './assets/routes.ts';
import { createAuth } from './auth/auth.ts';
import { authRoutes, createGuard } from './auth/plugin.ts';
import type { Services } from './context.ts';
import { insightsRoutes } from './insights/routes.ts';
import { meRoutes } from './me/routes.ts';
import { memoryRoutes } from './memories/routes.ts';
import { presetRoutes } from './presets/routes.ts';
import { syncRoutes } from './sync/routes.ts';

export interface ServiceDeps {
  config: AppConfig;
  database: Database;
  storage: Storage;
  jobs: JobQueue;
  mailer: Mailer;
}

export function createServices(deps: ServiceDeps): Services {
  const auth = createAuth(deps);
  return { ...deps, auth, guard: createGuard(auth) };
}

/** Every feature module of the modular monolith, in registration order (ADR-0006). */
export function createModules(services: Services): FastifyPluginAsync[] {
  return [
    authRoutes(services.auth, { signInPerMinute: services.config.limits.authPerMinute }),
    meRoutes(services),
    memoryRoutes(services),
    assetRoutes(services),
    syncRoutes(services),
    presetRoutes(services),
    albumRoutes(services),
    insightsRoutes(services),
  ];
}
