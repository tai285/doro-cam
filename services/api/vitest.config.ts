import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    // Integration tests share one Postgres and one S3 bucket; each file isolates itself with its
    // own database and key prefix, so files can run in parallel.
    testTimeout: 30_000,
    hookTimeout: 60_000,
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      // server.ts and worker.ts are five-line process entrypoints, exercised by test/entrypoints.test.ts
      // as real child processes (child-process coverage is not collected by v8 in this run).
      exclude: ['src/server.ts', 'src/worker.ts', 'src/db/migrate-cli.ts', 'src/**/*.d.ts'],
      reporter: ['text', 'lcov', 'json-summary'],
      thresholds: { statements: 95, branches: 90, functions: 95, lines: 95 },
    },
  },
});
