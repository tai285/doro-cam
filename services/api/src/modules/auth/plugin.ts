import rateLimit from '@fastify/rate-limit';
import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { UnauthenticatedError } from '../../lib/errors.ts';
import type { Auth } from './auth.ts';

export interface Principal {
  userId: string;
  email: string;
  sessionId: string;
}

export type Guard = (request: FastifyRequest) => Promise<Principal>;

function toHeaders(request: FastifyRequest): Headers {
  const headers = new Headers();
  for (const [name, value] of Object.entries(request.headers)) {
    if (Array.isArray(value)) {
      for (const item of value) {
        headers.append(name, item);
      }
    } else if (value !== undefined) {
      headers.set(name, value);
    }
  }
  return headers;
}

/** Resolves the caller from a session cookie or a bearer token, or throws 401 (PRIV-003: every request is authorized). */
export function createGuard(auth: Auth): Guard {
  return async (request) => {
    const result = await auth.api.getSession({ headers: toHeaders(request) });
    if (result === null || result === undefined) {
      throw new UnauthenticatedError();
    }
    return { userId: result.user.id, email: result.user.email, sessionId: result.session.id };
  };
}

/**
 * Mounts Better Auth under /v1/auth (sign-up, sign-in, verify email, reset, sign-out).
 * Sign-in and sign-up are rate limited per IP to slow credential stuffing.
 */
export function authRoutes(auth: Auth, options: { signInPerMinute: number } = { signInPerMinute: 30 }): FastifyPluginAsync {
  return async (app) => {
    await app.register(rateLimit, { max: options.signInPerMinute, timeWindow: '1 minute' });
    app.route({
      method: ['GET', 'POST'],
      url: '/v1/auth/*',
      handler: async (request, reply) => {
        const url = new URL(request.url, `${request.protocol}://${request.hostname}`);
        const hasBody = request.method !== 'GET' && request.body !== undefined && request.body !== null;
        const response = await auth.handler(
          new Request(url, {
            method: request.method,
            headers: toHeaders(request),
            ...(hasBody ? { body: JSON.stringify(request.body) } : {}),
          }),
        );
        void reply.status(response.status);
        response.headers.forEach((value, name) => {
          if (name.toLowerCase() !== 'set-cookie') {
            void reply.header(name, value);
          }
        });
        const cookies = response.headers.getSetCookie();
        if (cookies.length > 0) {
          void reply.header('set-cookie', cookies);
        }
        return reply.send(Buffer.from(await response.arrayBuffer()));
      },
    });
  };
}
