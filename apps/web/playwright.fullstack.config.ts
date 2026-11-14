import { defineConfig, devices } from '@playwright/test';

/**
 * The web half of the full-stack scenario (scripts/e2e-fullstack.sh). Unlike playwright.config.ts it starts
 * nothing: the script has already started the real API + worker, built and served the web app, and run the
 * Android app against the same stack. Addresses and the app account arrive through FULLSTACK_* variables.
 */
export default defineConfig({
  testDir: 'e2e-fullstack',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 15_000 },
  reporter: [['list']],
  use: {
    baseURL: process.env.FULLSTACK_WEB ?? 'http://127.0.0.1:4173',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
