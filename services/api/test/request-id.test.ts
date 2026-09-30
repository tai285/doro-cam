import { describe, expect, it } from 'vitest';
import { REQUEST_ID_HEADER, resolveRequestId } from '../src/lib/request-id.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe('resolveRequestId', () => {
  it('uses the header name x-request-id', () => {
    expect(REQUEST_ID_HEADER).toBe('x-request-id');
  });

  it('accepts a safe caller-supplied ID', () => {
    expect(resolveRequestId('client-req_12345.abc')).toBe('client-req_12345.abc');
  });

  it('uses the first value when the header is repeated', () => {
    expect(resolveRequestId(['first-id-123', 'second-id-456'])).toBe('first-id-123');
  });

  const rejected: ReadonlyArray<[string, string | string[] | undefined]> = [
    ['absent', undefined],
    ['empty', ''],
    ['too short', 'abc'],
    ['too long', 'a'.repeat(65)],
    ['containing spaces', 'has space in it'],
    ['containing a newline (log injection)', 'valid-id-1\nfake log line'],
    ['containing quotes', 'id"quoted"123'],
    ['an empty list', []],
  ];
  for (const [name, value] of rejected) {
    it(`replaces an ID that is ${name} with a fresh UUID`, () => {
      expect(resolveRequestId(value)).toMatch(UUID);
    });
  }

  it('generates different IDs each time', () => {
    expect(resolveRequestId(undefined)).not.toBe(resolveRequestId(undefined));
  });

  it('accepts the boundary lengths 8 and 64', () => {
    expect(resolveRequestId('a'.repeat(8))).toBe('a'.repeat(8));
    expect(resolveRequestId('a'.repeat(64))).toBe('a'.repeat(64));
  });
});
