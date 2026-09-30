# AGENTS.md — apps/web

React + TypeScript + Vite dashboard for the library and account management. It is **not** a camera and must not duplicate the mobile camera UI ([vision](../../docs/product/vision.md)). Read the root [AGENTS.md](../../AGENTS.md) first; this file adds only what is specific to this package. Design: [ux-principles.md](../../docs/design/ux-principles.md). API: [specs/api.md](../../docs/specs/api.md).

## Commands

Run from `apps/web` (or `pnpm --filter @doro/web <script>` from the repo root).

| Purpose | Command |
|---|---|
| Dev server (http://localhost:5173) | `pnpm dev` |
| Type check (TypeScript 7 `tsc`) | `pnpm typecheck` |
| Lint / format check | `pnpm lint` · `pnpm format:check` (`pnpm format` fixes) |
| Unit and component tests | `pnpm test` (with coverage and thresholds: `pnpm test:coverage`) |
| End-to-end tests in Chromium, Firefox, WebKit and a phone profile | `pnpm test:e2e` (builds, serves the preview, runs Playwright; first run needs `pnpm exec playwright install chromium firefox webkit`) |
| Production build | `pnpm build` |

## Rules specific to this package

- **No business logic or authorization here.** The server decides what a user may see; the UI only hides what it is told to hide. Never store tokens in `localStorage`: sessions use httpOnly cookies (ADR-0011).
- **Design tokens:** colors, spacing and type come from CSS variables in `src/styles/tokens.css`; never hard-code values in components. Any change to a token must keep the contrast tests (`src/styles/tokens.test.ts`) passing.
- **Accessibility is a requirement (NFR-007):**
  - one `h1` and one `main` per page, with the page title set through `usePageTitle`;
  - focus moves to the main region after navigation (`Layout`);
  - every interactive element is keyboard operable with a visible focus ring;
  - no horizontal scroll at 360 px width;
  - text must respect the user's font size (use `rem`, never pin the root size).
- **Server state** goes through TanStack Query (`createQueryClient` defaults). Presigned media URLs expire, so never cache them beyond their `expiresAt`.
- **Routes** are declared once in `src/app/routes.tsx` and shared by the browser router and the tests.
- **Strictness:** TypeScript strict flags are on, ESLint runs `strictTypeChecked`, `jsx-a11y` and the React hooks rules. Do not add `any`, `@ts-ignore` or lint suppressions without a comment that says why.
- **Toolchain note:** `typescript` is aliased to `@typescript/typescript6` because typescript-eslint cannot load TypeScript 7 yet; `@typescript/native` is TypeScript 7, which provides the `tsc` used here. Do not "fix" this by removing either alias until typescript-eslint supports TS 7.

## Tests

- Unit and component tests sit next to the code as `*.test.ts(x)` (Vitest + Testing Library + jsdom). `src/test/render.tsx` renders the real route table; `src/test/axe.ts` runs axe with the contrast rule off (jsdom has no canvas), because contrast is verified on the real token values instead.
- Every page has a test that it renders, sets its title and passes axe with no violations.
- End-to-end tests are in `e2e/` and run against the production build. Browser-specific behavior must be skipped with a stated reason, never silently (for example Safari does not Tab onto links).
- Tag tests with the requirement they cover: `it('[NFR-007] ...', ...)`.
- Coverage thresholds are in `vite.config.ts` (95% lines/statements/functions, 90% branches) and may not be lowered.
