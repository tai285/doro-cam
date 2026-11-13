/**
 * Test-only entrypoint for the Playwright end-to-end suite (apps/web/playwright.config.ts).
 * It boots the real API on a private database and the real S3, but with an in-memory mail outbox
 * (readable at GET /__test/outbox) and in-process jobs, so a browser test can complete email
 * verification and password reset without an inbox. Never used outside tests.
 */
import { startStack } from './helpers/stack.ts';

const port = Number(process.env.E2E_API_PORT ?? 4300);
const webOrigin = process.env.E2E_WEB_ORIGIN ?? 'http://127.0.0.1:4173';

const stack = await startStack(
  {
    PORT: String(port),
    HOST: '127.0.0.1',
    PUBLIC_BASE_URL: `http://127.0.0.1:${String(port)}`,
    WEB_ORIGINS: webOrigin,
    AUTH_RATE_LIMIT_PER_MINUTE: '100000',
    LOG_LEVEL: 'warn',
  },
  {
    extraModules: ({ mailer }) => [
      async (app) => {
        app.get('/__test/outbox', async () => ({ items: mailer.sent }));
        app.delete('/__test/outbox', async () => {
          mailer.sent.length = 0;
          return { ok: true };
        });
      },
    ],
  },
);

await stack.app.listen({ host: '127.0.0.1', port });
console.log(`e2e api listening on http://127.0.0.1:${String(port)}`);

let closing = false;
const shutdown = async () => {
  if (closing) return;
  closing = true;
  await stack.close();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown());
process.on('SIGINT', () => void shutdown());
