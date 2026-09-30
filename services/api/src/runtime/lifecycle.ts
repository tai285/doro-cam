export interface Closable {
  close(): Promise<void>;
}

export interface ProcessLike {
  once(event: 'SIGINT' | 'SIGTERM', listener: () => void): unknown;
  exit(code: number): never | void;
}

export interface LoggerLike {
  error(message: string, error?: unknown): void;
  info(message: string): void;
}

/**
 * Starts a service, then shuts it down cleanly on SIGINT/SIGTERM. A startup failure (for example
 * an invalid configuration) is printed and exits with code 1.
 */
export async function runUntilSignal(
  start: () => Promise<Closable>,
  proc: ProcessLike = process,
  log: LoggerLike = {
    error: (message, error) => console.error(message, error instanceof Error ? error.message : error ?? ''),
    info: (message) => console.log(message),
  },
): Promise<void> {
  let service: Closable;
  try {
    service = await start();
  } catch (error) {
    log.error('Startup failed:', error);
    proc.exit(1);
    return;
  }

  let stopping = false;
  const shutdown = (signal: string) => {
    if (stopping) {
      return;
    }
    stopping = true;
    log.info(`${signal} received, shutting down...`);
    service.close().then(
      () => proc.exit(0),
      (error: unknown) => {
        log.error('Shutdown failed:', error);
        proc.exit(1);
      },
    );
  };
  proc.once('SIGINT', () => shutdown('SIGINT'));
  proc.once('SIGTERM', () => shutdown('SIGTERM'));
}
