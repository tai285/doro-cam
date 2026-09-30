# Local Development

Status: Living (partially planned) · Last updated: 2026-09-30 · Related: ADR-0012, ADR-0013

## Available now

| Tool | Version (verified 2026-09-30) | Used for |
|---|---|---|
| Git | 2.52 | Version control |
| Node.js | 24.12 | Repo tooling (`tools/docs-check`), later API and web |
| GitHub CLI | 2.102 (`C:\Program Files\GitHub CLI\gh.exe`; logged in as `tai285`) | Repo and CI operations, triggering iOS cloud builds |
| Docker Desktop | 29.1 (WSL2 backend; start it if `docker info` fails) | Local Postgres and Garage S3 |
| Hypervisor | present (WSL2/Hyper-V) | The Android Emulator must use WHPX (see below) |

```sh
pnpm install         # installs workspace dependencies (pnpm 12.8.1, pinned by packageManager)
pnpm test:tools      # tooling and script tests only (no Docker needed)
pnpm test            # tests in every TypeScript package (the API's need `pnpm infra:up` first)
pnpm typecheck       # tsc --noEmit in every TypeScript package
pnpm check:docs      # documentation integrity
```

pnpm is installed per user with `npm install -g pnpm` (Corepack's `enable` needs admin rights to write into the nvm-managed Node folder on this machine). If `pnpm` isn't found in a new shell, add `%APPDATA%\npm` to `PATH` (or dot-source `scripts/dev-env.ps1`).

## Mobile toolchain (installed user-level, no admin needed)

Everything lives under `%USERPROFILE%\dev` (override with `DORO_DEV_HOME`). Load it into a shell with:

```sh
source scripts/dev-env.sh        # Git Bash
. .\scripts\dev-env.ps1          # PowerShell
```

| Tool | Version (verified 2026-10-01) | Notes |
|---|---|---|
| Flutter (stable) | 3.47.5 (Dart 3.13.4) | `git clone -b stable` into `dev\flutter`; analytics disabled |
| JDK | Temurin 17.0.20 | The machine's system `JAVA_HOME` points at a stale JDK 1.6; `dev-env` overrides it per session and the user-level variable was set too |
| Android SDK | platform 35 and 36, build-tools 35.0.0, 36.0.0 and 28.0.3, NDK 28.2.13676358, platform-tools, emulator 37.1 | Flutter 3.47 requires platform 36 and build-tools 28.0.3; the NDK must be installed explicitly or Gradle fails |
| System image | `system-images;android-35;google_apis;x86_64` | AVD `doro_api35` |
| Windows Hypervisor Platform | present and usable | `emulator -accel-check` reports "WHPX is installed and usable"; no admin step was needed |
| Cloud macOS (iOS) | not yet set up | GitHub Actions `macos-*` and Codemagic (FND-T-009) |

`flutter doctor` is green for Flutter, Android toolchain, Chrome and network. The only warning is Visual Studio (Windows-desktop apps), which we don't build.

### Installing the Android SDK (reproduction notes)

- `sdkmanager` is deprecated in favor of Google's new Android CLI but still works. Package names contain `;`, which the `.bat` wrapper splits on, so quote them from `cmd`: `cmd /c "echo y| sdkmanager.bat --sdk_root=... \"platforms;android-35\""`.
- `--licenses` prints a warning and isn't needed on the current tools.
- A first `flutter build apk` takes about 4 minutes (Gradle and dependency downloads); later builds take under a minute.

### Android Emulator on Windows

1. Create the standard AVD (the name is used by scripts and docs):
   `avdmanager create avd -n doro_api35 -k "system-images;android-35;google_apis;x86_64" -d pixel_7`
   then set `hw.camera.back=virtualscene`, `hw.camera.front=emulated`, `hw.ramSize=3072` in the AVD `config.ini`. (Done on this machine.)
2. Run headless for tests: `bash scripts/emulator-start.sh` (boots `doro_api35`, waits for Android's boot-completed signal with a timeout, reuses an emulator that is already running, and prints the serial). It boots in about 40-60 seconds here. Stop it with `adb emu kill`.
3. Run tests on it: `cd apps/mobile && flutter test integration_test -d emulator-5554`.
4. The emulator reaches the host's local API and S3 (`10.0.2.2:9000`) without `adb reverse`.

Acceleration must use the Windows Hypervisor Platform because WSL2/Hyper-V is active. If `emulator -accel-check` ever reports it unavailable, the owner enables *Windows Hypervisor Platform* once (admin), then reboots; agents must ask rather than attempt elevation.

Resource note: 16 GB RAM is tight. One emulator (about 3 GB with its guest) plus Docker Desktop, VS Code and a browser leaves only a few GB free, and once memory runs out everything slows dramatically: a 7-second script test took 8 minutes while the emulator sat idle in the background. **Stop the emulator when you are not running device tests** (`adb emu kill`), and never run two. Closing Docker Desktop when the API tests are not needed also helps.

### iOS without a Mac

- Every iOS build and test runs in the cloud (ADR-0013). Agents push a branch, then run `gh workflow run ios.yml --ref <branch>`, `gh run watch`, and `gh run view --log-failed`.
- The repository is **public**, so GitHub-hosted runners (including macOS) are free and unlimited. Codemagic stays available as an overflow runner.
- Simulator camera: none. Debug and test builds use the plugin's synthetic camera source (ADR-0013).

### Local services (`infrastructure/docker-compose.yml`)

```sh
pnpm infra:up          # starts Postgres + Garage S3, bootstraps bucket, key, CORS, lifecycle (idempotent)
pnpm infra:down        # stops the stack, keeps data (add -- --volumes to wipe it)
pnpm test:infra        # live-stack protocol tests (needs infra:up first)
```

| Service | Host port | Purpose |
|---|---|---|
| postgres (17) | 5432 (`POSTGRES_PORT`) | Metadata + pg-boss |
| garage (S3) | 9000 (`S3_PORT`) | S3-compatible storage (ADR-0014). Bucket `doro-media`, public dev key from `.env.example` |

Both are bound to `127.0.0.1` only, and the credentials are public dev-only values. `pnpm infra:up` creates the bucket, imports the dev key, and applies CORS and the abort-incomplete-multipart lifecycle rule using the S3 API, so the same code works against R2 or S3 later. Copy `.env.example` to `.env` to override anything.

### Planned commands

```sh
docker compose -f infrastructure/docker-compose.yml up -d
pnpm --filter api dev          # API on :3000
pnpm --filter api worker:dev   # worker
pnpm --filter @doro/web dev     # web on :5173
cd apps/mobile && flutter run -d emulator-5554
```

### Optional: owner's physical devices (field verification only)

- **Honor X9c:** enable Developer options, then USB debugging. Install the CI debug APK artifact with `adb install`. The phone reaches the local API via `adb reverse tcp:3000 tcp:3000` and `adb reverse tcp:9000 tcp:9000`.
- **iPhone 12 Pro Max:** needs TestFlight, which requires the Apple Developer Program (an owner decision).

## Windows notes

- Keep LF line endings. `.gitattributes` enforces this, and `core.autocrlf=false` is set in the repo.
- Avoid path-length issues: enable long paths (`git config core.longpaths true`) if Gradle complains. The repo path contains a space (`Doro Cam`), so always quote paths in scripts.
- Commands in docs are POSIX. PowerShell equivalents are given where they differ. In PowerShell, run `gh ... --jq` through the Bash tool, because PowerShell splits the quoted jq expressions.
