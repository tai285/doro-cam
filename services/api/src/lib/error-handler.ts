import type { FastifyError, FastifyInstance } from 'fastify';
import { hasZodFastifySchemaValidationErrors, isResponseSerializationError } from 'fastify-type-provider-zod';
import { AppError, BadRequestError, internalEnvelope, NotFoundError, toEnvelope } from './errors.ts';

/** Fastify-generated 4xx errors (bad JSON, body too large, ...) mapped to stable API codes. */
const FRAMEWORK_CODES = new Map<number, { code: string; message: string }>([
  [413, { code: 'request.too_large', message: 'The request body is too large.' }],
  [415, { code: 'request.unsupported_media_type', message: 'The content type is not supported.' }],
]);
const DEFAULT_CLIENT_ERROR = { code: 'request.invalid', message: 'The request is invalid.' };

function isClientFastifyError(error: unknown): error is FastifyError & { statusCode: number } {
  // Object() makes this safe for null, undefined and primitives without extra branches.
  const statusCode: unknown = (Object(error) as { statusCode?: unknown }).statusCode;
  return typeof statusCode === 'number' && statusCode >= 400 && statusCode < 500;
}

/**
 * A handler threw something that is not an Error (for example a string). The original is kept as
 * `cause`, and a short description goes into the message so it survives log serialization. This
 * message is only ever logged: clients receive the generic internal envelope.
 */
export class NonErrorThrown extends Error {
  constructor(thrown: unknown) {
    super(`A non-Error value was thrown: ${String(thrown).slice(0, 200)}`, { cause: thrown });
    this.name = 'NonErrorThrown';
  }
}

/**
 * Fastify's own error path throws a TypeError when a handler rejects with a primitive, which would
 * bypass our handler and leak the thrown text in Fastify's default response. Wrapping every route
 * handler turns primitives into a proper Error first, so all failures take the same path.
 */
function normalizeThrownValues(app: FastifyInstance): void {
  app.addHook('onRoute', (routeOptions) => {
    const original = routeOptions.handler;
    routeOptions.handler = async function (this: FastifyInstance, request, reply) {
      try {
        return await original.call(this, request, reply);
      } catch (thrown) {
        throw typeof thrown === 'object' && thrown !== null ? thrown : new NonErrorThrown(thrown);
      }
    };
  });
}

/**
 * Installs the single error and 404 handlers. Every failure leaves the API as the documented
 * envelope (docs/specs/api.md). Unexpected errors are logged in full but never described to the client.
 */
export function registerErrorHandling(app: FastifyInstance): void {
  normalizeThrownValues(app);
  app.setErrorHandler((error: unknown, request, reply) => {
    const requestId = request.id;

    if (error instanceof AppError) {
      if (error.statusCode >= 500) {
        request.log.error({ err: error }, 'request failed');
      }
      return reply.status(error.statusCode).send(toEnvelope(error, requestId));
    }

    if (hasZodFastifySchemaValidationErrors(error)) {
      const details = error.validation.map((issue) => ({
        path: issue.instancePath,
        message: issue.message ?? 'is invalid',
        rule: issue.keyword,
      }));
      return reply.status(400).send(toEnvelope(new BadRequestError('The request is invalid.', details), requestId));
    }

    if (isResponseSerializationError(error)) {
      // A handler produced data that breaks its own response schema: a server bug, never the client's fault.
      request.log.error({ err: error }, 'response did not match its schema');
      return reply.status(500).send(internalEnvelope(requestId));
    }

    if (isClientFastifyError(error)) {
      const mapped = FRAMEWORK_CODES.get(error.statusCode) ?? DEFAULT_CLIENT_ERROR;
      const appError = new AppError(error.statusCode, mapped.code, mapped.message);
      return reply.status(appError.statusCode).send(toEnvelope(appError, requestId));
    }

    request.log.error({ err: error }, 'unhandled error');
    return reply.status(500).send(internalEnvelope(requestId));
  });

  app.setNotFoundHandler((request, reply) => {
    return reply
      .status(404)
      .send(toEnvelope(new NotFoundError(`No route for ${request.method} ${request.url.split('?')[0]}.`, 'route.not_found'), request.id));
  });
}
