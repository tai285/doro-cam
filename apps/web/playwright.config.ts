import { defineConfig, devices } from '@playwright/test';

const WEB_PORT = 4173;
const API_PORT = 4300;
const WEB = `http://127.0.0.1:${String(WEB_PORT)}`;
const API = `http://127.0.0.1:${String(API_PORT)}`;

/**
 * End-to-end tests run the real stack: the built web app, the real API (private Postgres database,
 * Garage S3, in-process jobs and an inspectable mail outbox, see services/api/test/e2e-server.ts).
 * Prerequisite: `pnpm infra:up` (Postgres + S3). Tests are tagged @cross when they should also run
 * in Firefox and WebKit; everything runs in Chromium and in a Pixel 7 viewport.
 */
export default defineConfig({
  testDir: 'e2e',
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  workers: 2,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: { baseURL: WEB, trace: 'retain-on-failure' },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] }, grep: /@cross/ },
    { name: 'webkit', use: { ...devices['Desktop Safari'] }, grep: /@cross/ },
    { name: 'mobile-chrome', use: { ...devices['Pixel 7'] } },
  ],
  webServer: [
    {
      command: 'node test/e2e-server.ts',
      cwd: '../../services/api',
      url: `${API}/healthz`,
      reuseExistingServer: false,
      timeout: 120_000,
      env: { E2E_API_PORT: String(API_PORT), E2E_WEB_ORIGIN: WEB },
    },
    {
      command: `pnpm build && pnpm preview --host 127.0.0.1 --port ${String(WEB_PORT)} --strictPort`,
      url: WEB,
      reuseExistingServer: false,
      timeout: 180_000,
      env: { VITE_API_URL: API },
    },
  ],
});
