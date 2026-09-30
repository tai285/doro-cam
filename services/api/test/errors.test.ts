import { describe, expect, it } from 'vitest';
import {
  AppError,
  BadRequestError,
  ConflictError,
  ForbiddenError,
  internalEnvelope,
  NotFoundError,
  RateLimitedError,
  ServiceUnavailableError,
  toEnvelope,
  UnauthenticatedError,
} from '../src/lib/errors.ts';

describe('error classes', () => {
  const cases: ReadonlyArray<[string, AppError, number, string]> = [
    ['BadRequestError', new BadRequestError(), 400, 'request.invalid'],
    ['UnauthenticatedError', new UnauthenticatedError(), 401, 'auth.unauthenticated'],
    ['ForbiddenError', new ForbiddenError(), 403, 'auth.forbidden'],
    ['NotFoundError', new NotFoundError(), 404, 'resource.not_found'],
    ['ConflictError', new ConflictError('Exists.'), 409, 'conflict'],
    ['RateLimitedError', new RateLimitedError(), 429, 'rate_limited'],
    ['ServiceUnavailableError', new ServiceUnavailableError(), 503, 'service.unavailable'],
  ];
  for (const [name, error, status, code] of cases) {
    it(`${name} maps to ${status} ${code}`, () => {
      expect(error).toBeInstanceOf(AppError);
      expect(error).toBeInstanceOf(Error);
      expect(error.name).toBe(name);
      expect(error.statusCode).toBe(status);
      expect(error.code).toBe(code);
      expect(error.message.length).toBeGreaterThan(0);
    });
  }

  it('allows custom messages, codes and details', () => {
    const error = new ConflictError('Version mismatch.', 'memory.version_conflict', { current: 4 });
    expect(error.code).toBe('memory.version_conflict');
    expect(error.details).toEqual({ current: 4 });
    expect(new NotFoundError('No such album.', 'album.not_found').code).toBe('album.not_found');
    expect(new BadRequestError('Bad.', [{ path: '/x' }], 'upload.too_large').code).toBe('upload.too_large');
    expect(new UnauthenticatedError('Sign in.', 'auth.expired').code).toBe('auth.expired');
    expect(new ForbiddenError('No.', 'album.forbidden').code).toBe('album.forbidden');
  });

  it('RateLimitedError carries the retry hint only when given', () => {
    expect(new RateLimitedError('Slow down.', 30).details).toEqual({ retryAfterSeconds: 30 });
    expect(new RateLimitedError().details).toBeUndefined();
  });
});

describe('envelopes', () => {
  it('serializes code, message and requestId, omitting absent details', () => {
    expect(toEnvelope(new NotFoundError('No such memory.', 'memory.not_found'), 'req-1')).toEqual({
      error: { code: 'memory.not_found', message: 'No such memory.', requestId: 'req-1' },
    });
  });

  it('includes details when present', () => {
    const envelope = toEnvelope(new ConflictError('Exists.', 'memory.conflict', { id: 'm1' }), 'req-2');
    expect(envelope.error.details).toEqual({ id: 'm1' });
  });

  it('produces a generic internal envelope that describes nothing', () => {
    expect(internalEnvelope('req-3')).toEqual({
      error: { code: 'internal', message: 'Something went wrong on our side.', requestId: 'req-3' },
    });
  });
});
