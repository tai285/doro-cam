import { loadConfig } from './config/env.ts';
import { runUntilSignal } from './runtime/lifecycle.ts';
import { startWorker } from './runtime/worker.ts';

await runUntilSignal(() => startWorker(loadConfig()));
