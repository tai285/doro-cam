import { drizzleAdapter } from '@better-auth/drizzle-adapter';
import { betterAuth } from 'better-auth';
import { bearer } from 'better-auth/plugins';
import { eq } from 'drizzle-orm';
import type { AppConfig } from '../../config/env.ts';
import type { Database } from '../../db/client.ts';
import * as schema from '../../db/schema.ts';
import type { Mailer } from '../../lib/mailer.ts';

export interface AuthDeps {
  config: AppConfig;
  database: Database;
  mailer: Mailer;
}

/**
 * Better Auth on our Postgres (ADR-0011). Web uses httpOnly cookies, mobile uses bearer tokens; both
 * are per-device sessions. Email verification is required before sign-in (AUTH-001).
 */
export function createAuth({ config, database, mailer }: AuthDeps) {
  return betterAuth({
    appName: 'Doro Cam',
    baseURL: config.auth.baseUrl,
    basePath: '/v1/auth',
    secret: config.auth.secret,
    trustedOrigins: config.auth.webOrigins,
    database: drizzleAdapter(database.db, { provider: 'pg', schema }),
    advanced: { database: { generateId: 'uuid' } },
    rateLimit: { enabled: false },
    emailAndPassword: {
      enabled: true,
      requireEmailVerification: true,
      minPasswordLength: 10,
      maxPasswordLength: 128,
      resetPasswordTokenExpiresIn: 60 * 60,
      sendResetPassword: async ({ user, url }) => {
        await mailer.send({
          kind: 'reset_password',
          to: user.email,
          subject: 'Reset your Doro Cam password',
          text: `Reset your password: ${url}`,
          link: url,
        });
      },
    },
    emailVerification: {
      sendOnSignUp: true,
      autoSignInAfterVerification: true,
      sendVerificationEmail: async ({ user, url }) => {
        await mailer.send({
          kind: 'verify_email',
          to: user.email,
          subject: 'Verify your Doro Cam email',
          text: `Confirm your email address: ${url}`,
          link: url,
        });
      },
    },
    session: { expiresIn: 60 * 60 * 24 * 30, updateAge: 60 * 60 * 24 },
    plugins: [bearer()],
    databaseHooks: {
      user: {
        create: {
          after: async (created) => {
            await database.db.insert(schema.usersProfile).values({ userId: created.id }).onConflictDoNothing();
          },
        },
      },
    },
  });
}

export type Auth = ReturnType<typeof createAuth>;

export async function loadCredentialHash(database: Database, userId: string): Promise<string | null> {
  const rows = await database.db
    .select({ password: schema.account.password })
    .from(schema.account)
    .where(eq(schema.account.userId, userId));
  return rows.find((row) => row.password !== null)?.password ?? null;
}
