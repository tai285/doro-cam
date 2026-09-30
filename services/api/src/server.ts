import { loadConfig } from './config/env.ts';
import { startApi } from './runtime/api.ts';
import { runUntilSignal } from './runtime/lifecycle.ts';

await runUntilSignal(() => startApi(loadConfig()));
