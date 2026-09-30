import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  server: { port: 5173 },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['src/test/setup.ts'],
    css: false,
    // Cold transforms are slow on Windows; cache them between runs.
    fsModuleCache: true,
    coverage: {
      provider: 'v8',
      include: ['src/**/*.{ts,tsx}'],
      // main.tsx only mounts the app into the page; the Playwright smoke test covers it.
      exclude: ['src/main.tsx', 'src/**/*.test.{ts,tsx}', 'src/test/**', 'src/vite-env.d.ts'],
      reporter: ['text', 'lcov', 'json-summary'],
      thresholds: { statements: 95, branches: 90, functions: 95, lines: 95 },
    },
  },
});
