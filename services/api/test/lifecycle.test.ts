import { describe, expect, it, vi } from 'vitest';
import { type Closable, type LoggerLike, type ProcessLike, runUntilSignal } from '../src/runtime/lifecycle.ts';

function fakeProcess() {
  const handlers = new Map<string, () => void>();
  const exits: number[] = [];
  const proc: ProcessLike = {
    once(event, listener) {
      handlers.set(event, listener);
    },
    exit(code) {
      exits.push(code);
    },
  };
  return { proc, handlers, exits };
}

function fakeLogger() {
  const lines: string[] = [];
  const log: LoggerLike = {
    error: (message, error) => lines.push(`error: ${message} ${error instanceof Error ? error.message : String(error ?? '')}`),
    info: (message) => lines.push(`info: ${message}`),
  };
  return { log, lines };
}

describe('runUntilSignal', () => {
  it('starts the service and registers SIGINT and SIGTERM handlers without exiting', async () => {
    const { proc, handlers, exits } = fakeProcess();
    const { log } = fakeLogger();
    const service: Closable = { close: vi.fn(async () => undefined) };

    await runUntilSignal(async () => service, proc, log);

    expect([...handlers.keys()].sort()).toEqual(['SIGINT', 'SIGTERM']);
    expect(exits).toEqual([]);
    expect(service.close).not.toHaveBeenCalled();
  });

  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    it(`closes the service and exits 0 on ${signal}`, async () => {
      const { proc, handlers, exits } = fakeProcess();
      const { log, lines } = fakeLogger();
      const service: Closable = { close: vi.fn(async () => undefined) };
      await runUntilSignal(async () => service, proc, log);

      handlers.get(signal)?.();

      await vi.waitFor(() => expect(exits).toEqual([0]));
      expect(service.close).toHaveBeenCalledTimes(1);
      expect(lines).toEqual([`info: ${signal} received, shutting down...`]);
    });
  }

  it('ignores a second signal while shutting down', async () => {
    const { proc, handlers, exits } = fakeProcess();
    const { log } = fakeLogger();
    let finishClose: () => void = () => undefined;
    const service: Closable = {
      close: vi.fn(() => new Promise<void>((resolve) => (finishClose = resolve))),
    };
    await runUntilSignal(async () => service, proc, log);

    handlers.get('SIGINT')?.();
    handlers.get('SIGTERM')?.();
    finishClose();

    await vi.waitFor(() => expect(exits).toEqual([0]));
    expect(service.close).toHaveBeenCalledTimes(1);
  });

  it('exits 1 and logs when shutdown fails', async () => {
    const { proc, handlers, exits } = fakeProcess();
    const { log, lines } = fakeLogger();
    const service: Closable = { close: async () => Promise.reject(new Error('pool stuck')) };
    await runUntilSignal(async () => service, proc, log);

    handlers.get('SIGTERM')?.();

    await vi.waitFor(() => expect(exits).toEqual([1]));
    expect(lines).toContain('error: Shutdown failed: pool stuck');
  });

  it('exits 1 without registering handlers when startup fails', async () => {
    const { proc, handlers, exits } = fakeProcess();
    const { log, lines } = fakeLogger();

    await runUntilSignal(async () => Promise.reject(new Error('invalid configuration')), proc, log);

    expect(exits).toEqual([1]);
    expect(handlers.size).toBe(0);
    expect(lines).toEqual(['error: Startup failed: invalid configuration']);
  });

  it('logs non-Error startup failures too', async () => {
    const { proc, exits } = fakeProcess();
    const { log, lines } = fakeLogger();
    await runUntilSignal(async () => Promise.reject('plain string'), proc, log);
    expect(exits).toEqual([1]);
    expect(lines).toEqual(['error: Startup failed: plain string']);
  });

  it('logs to the console by default', async () => {
    const { proc, handlers, exits } = fakeProcess();
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const infoSpy = vi.spyOn(console, 'log').mockImplementation(() => undefined);
    try {
      await runUntilSignal(async () => Promise.reject(new Error('bad config')), proc);
      expect(errorSpy).toHaveBeenCalledWith('Startup failed:', 'bad config');

      await runUntilSignal(async () => Promise.reject('text only'), proc);
      expect(errorSpy).toHaveBeenCalledWith('Startup failed:', 'text only');

      await runUntilSignal(async () => ({ close: async () => undefined }), proc);
      handlers.get('SIGINT')?.();
      await vi.waitFor(() => expect(exits).toContain(0));
      expect(infoSpy).toHaveBeenCalledWith('SIGINT received, shutting down...');

      const failing = fakeProcess();
      await runUntilSignal(async () => ({ close: async () => Promise.reject(new Error('stuck')) }), failing.proc);
      failing.handlers.get('SIGTERM')?.();
      await vi.waitFor(() => expect(failing.exits).toEqual([1]));
      expect(errorSpy).toHaveBeenCalledWith('Shutdown failed:', 'stuck');

      const noMessage = fakeProcess();
      await runUntilSignal(async () => Promise.reject(undefined), noMessage.proc);
      expect(errorSpy).toHaveBeenCalledWith('Startup failed:', '');
    } finally {
      errorSpy.mockRestore();
      infoSpy.mockRestore();
    }
  });
});
