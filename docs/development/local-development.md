# Local Development

Status: Living · Last updated: 2026-11-14 · Related: ADR-0012, ADR-0013, ADR-0014, ADR-0016

All development tooling and **every test suite runs inside WSL2 Ubuntu** (owner decision, ADR-0016). The working tree lives on Windows and is the copy that gets committed; WSL gets a fast ext4 mirror of it. There is no CI that runs on push. The one automation that exists is the manually dispatched `ios.yml` for cloud macOS (see [iOS without a Mac](#ios-without-a-mac)).

## One-time WSL setup

Installed user-level or via `apt` in the Ubuntu distribution (done on the owner's machine, 2026-11-13):

| Tool | Version | Notes |
|---|---|---|
| Node.js | 24.x | `engines.node >= 24` |
| pnpm | 12.8.1 | pinned by `packageManager`; `npm i -g pnpm@12.8.1` |
| JDK | OpenJDK 17 | `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` |
| Flutter | 3.47.7 (Dart 3.13.5) | `git clone -b 3.47.7` into `~/dev/flutter` |
| Android SDK | platform 35 and 36, build-tools 35.0.0 and 36.0.0, emulator, platform-tools, system image `system-images;android-35;google_apis;x86_64` | `~/dev/android-sdk` |
| AVD | `doro_api35` (Pixel 6 profile, KVM-accelerated) | `hw.camera.back=virtualscene` |
| Docker Engine + Compose v2 | `docker.io`, `docker-compose-v2` | run `dockerd` inside WSL (`nohup dockerd &`) |
| Playwright browsers | Chromium (and Firefox, WebKit when needed) | `pnpm exec playwright install --with-deps` |

Load the toolchain in a WSL shell with `source scripts/dev-env.sh` (sets `JAVA_HOME`, `ANDROID_HOME` and `PATH`).

## Working from Windows

The repository path contains a space (`Doro Cam`), so always quote it. The helper scripts do the quoting for you:

```sh
# mirror the Windows tree into ~/doro-cam (never copies node_modules, build outputs or .git)
wsl -e bash "/mnt/c/Users/yying/dev/scratch/Doro Cam/Doro Cam/scripts/wsl-sync.sh"

# mirror, run a command in the WSL tree, then copy dependency manifests, the lockfile,
# Drizzle migrations and the generated OpenAPI back to the Windows tree
wsl -e bash "/mnt/c/Users/yying/dev/scratch/Doro Cam/Doro Cam/scripts/wsl-run.sh" 'pnpm --filter @doro/api test'
```

Set `DORO_WSL_TREE` to use a different WSL directory (several people or agents can work at once). Keep LF line endings (`.gitattributes` enforces them).

## Everyday commands (run in the WSL tree)

```sh
pnpm install              # workspace dependencies
pnpm infra:up             # Postgres 17 + Garage S3 (bootstraps bucket, key, CORS, lifecycle rule)
pnpm test                 # every TypeScript package (API tests need infra:up)
pnpm typecheck            # tsc --noEmit everywhere
pnpm check:docs           # documentation integrity
pnpm check:traceability   # every requirement of a done task has a tagged test
pnpm check:coverage -- --only services/api    # coverage gate (floor + ratchet)
pnpm --filter @doro/api openapi               # regenerate packages/api-contract/openapi.json
pnpm --filter @doro/web test:e2e              # Playwright end to end
```

### Local services (`infrastructure/docker-compose.yml`)

| Service | Host port | Purpose |
|---|---|---|
| postgres (17) | 5432 (`POSTGRES_PORT`) | Metadata and pg-boss |
| garage (S3) | 9000 (`S3_PORT`) | S3-compatible storage (ADR-0014). Bucket `doro-media`, public dev key from `.env.example` |

Both bind to `127.0.0.1` only and use public dev-only credentials. Copy `.env.example` to `.env` to override anything.

### Running the whole product locally

```sh
pnpm infra:up
pnpm --filter @doro/api db:migrate      # apply migrations
pnpm --filter @doro/api dev             # API on :3000 (verification and reset emails are written to its log)
pnpm --filter @doro/api worker:dev      # worker (verify, derivatives, purge, sweeps)
pnpm --filter @doro/web dev             # dashboard on :5173
source scripts/dev-env.sh && cd apps/mobile && flutter run -d emulator-5554
```

## Android Emulator in WSL

KVM is available in WSL2, so the emulator is hardware-accelerated.

1. `bash scripts/emulator-start.sh` boots the headless `doro_api35` AVD, waits for Android's boot-completed signal, reuses an emulator that is already running and prints the serial. Stop it with `adb emu kill`.
2. Run tests: `cd apps/mobile && flutter test integration_test -d emulator-5554`.
3. The emulator reaches services in WSL through `10.0.2.2` (for example the API on `10.0.2.2:3000`).

Resource note: WSL has about 7 GB of RAM. One emulator (about 3 GB with its guest) plus Docker, Postgres and a browser is the limit. Stop the emulator when you are not running device tests, and never run two.

## iOS without a Mac

There is no local Mac. iOS is built and tested only on GitHub-hosted cloud macOS through `.github/workflows/ios.yml`, which is **manual dispatch only**; nothing runs on push or pull request (ADR-0016).

- Trigger it with `bash scripts/ios-ci.sh [branch]`. It dispatches the workflow, waits and prints the failing logs. Equivalent manual commands: `gh workflow run ios.yml --ref <branch>`, `gh run watch`, `gh run view --log-failed`.
- The repository is public, so macOS runners are free. A run takes about 9 minutes.
- The workflow has two jobs: Swift core unit tests (`DOROCAM_SWIFT_STANDALONE=1 swift test`, no simulator) and the iOS Simulator job (build, synthetic-camera marker checks, `integration_test` with the plugin's synthetic camera).
- The iOS Simulator has no camera. Debug builds use the plugin's synthetic camera source (ADR-0013); release builds must never contain it.
- Until a run has passed for a change, record its iOS part as unverified in [field-verification.md](field-verification.md).

## Physical devices (optional, field verification only)

- **Honor X9c:** enable Developer options and USB debugging. Build a debug APK and install it with `adb install` (from Windows, or forward the device to WSL with `usbipd`). The phone reaches the local API through `adb reverse tcp:3000 tcp:3000` and `adb reverse tcp:9000 tcp:9000`.
- **iPhone 12 Pro Max:** needs a signed build; TestFlight requires the Apple Developer Program (an owner decision). iPhone entries stay `pending` until then.

## Notes

- Commands in docs are POSIX shell. Run them in WSL.
- Tests never run in the Windows environment; this avoids path, shell and line-ending differences.
- A cold first install is slow; later runs use caches.
