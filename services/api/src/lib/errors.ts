/**
 * Application errors and the wire format for them (docs/specs/api.md):
 *   { "error": { "code": "memory.not_found", "message": "...", "details": {...}?, "requestId": "..." } }
 * Codes are stable strings that clients may switch on. Messages are for humans.
 */

export interface ErrorEnvelope {
  error: {
    code: string;
    message: string;
    details?: unknown;
    requestId: string;
  };
}

export class AppError extends Error {
  readonly code: string;
  readonly statusCode: number;
  readonly details: unknown;

  constructor(statusCode: number, code: string, message: string, details?: unknown) {
    super(message);
    this.name = new.target.name;
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }
}

export class BadRequestError extends AppError {
  constructor(message = 'The request is invalid.', details?: unknown, code = 'request.invalid') {
    super(400, code, message, details);
  }
}

export class UnauthenticatedError extends AppError {
  constructor(message = 'Authentication is required.', code = 'auth.unauthenticated') {
    super(401, code, message);
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'You are not allowed to do that.', code = 'auth.forbidden') {
    super(403, code, message);
  }
}

/** Also used when the caller may not know a resource exists: never reveal existence by returning 403 (docs/architecture/security.md). */
export class NotFoundError extends AppError {
  constructor(message = 'Not found.', code = 'resource.not_found') {
    super(404, code, message);
  }
}

export class ConflictError extends AppError {
  constructor(message: string, code = 'conflict', details?: unknown) {
    super(409, code, message, details);
  }
}

export class RateLimitedError extends AppError {
  constructor(message = 'Too many requests.', retryAfterSeconds?: number) {
    super(429, 'rate_limited', message, retryAfterSeconds === undefined ? undefined : { retryAfterSeconds });
  }
}

export class ServiceUnavailableError extends AppError {
  constructor(message = 'The service is temporarily unavailable.', details?: unknown) {
    super(503, 'service.unavailable', message, details);
  }
}

export function toEnvelope(error: AppError, requestId: string): ErrorEnvelope {
  return {
    error: {
      code: error.code,
      message: error.message,
      ...(error.details === undefined ? {} : { details: error.details }),
      requestId,
    },
  };
}

export function internalEnvelope(requestId: string): ErrorEnvelope {
  return {
    error: { code: 'internal', message: 'Something went wrong on our side.', requestId },
  };
}
