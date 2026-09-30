import { describe, expect, it } from 'vitest';
import { TimeoutError, withTimeout } from '../src/lib/timeout.ts';

describe('withTimeout', () => {
  it('resolves with the value when the promise settles in time', async () => {
    await expect(withTimeout(Promise.resolve(42), 1000, 'quick')).resolves.toBe(42);
  });

  it('propagates the original rejection', async () => {
    await expect(withTimeout(Promise.reject(new Error('boom')), 1000, 'failing')).rejects.toThrow('boom');
  });

  it('rejects with a TimeoutError naming the operation when it takes too long', async () => {
    const started = Date.now();
    const never = new Promise<never>(() => undefined);
    await expect(withTimeout(never, 50, 'slow op')).rejects.toSatisfy((error: unknown) => {
      return error instanceof TimeoutError && error.message === 'slow op timed out after 50 ms';
    });
    expect(Date.now() - started).toBeGreaterThanOrEqual(45);
    expect(Date.now() - started).toBeLessThan(1000);
  });

  it('does not reject later once the promise has settled (timer cleared)', async () => {
    const value = await withTimeout(new Promise<string>((resolve) => setTimeout(() => resolve('ok'), 10)), 60, 'settled');
    expect(value).toBe('ok');
    await new Promise((resolve) => setTimeout(resolve, 120));
  });
});
