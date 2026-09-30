# Local Development

Status: Living (partially planned) · Last updated: 2026-09-30 · Related: ADR-0012, ADR-0013

## Available now

| Tool | Version (verified 2026-09-30) | Used for |
|---|---|---|
| Git | 2.52 | Version control |
| Node.js | 24.12 | Repo tooling (`tools/docs-check`), later API and web |
| GitHub CLI | 2.102 (`C:\Program Files\GitHub CLI\gh.exe`; logged in as `tai285`) | Repo and CI operations, triggering iOS cloud builds |
| Docker Desktop | installed (WSL2 backend) | Local Postgres and MinIO (planned) |
| Hypervisor | present (WSL2/Hyper-V) | The Android Emulator must use WHPX (see below) |

```sh
pnpm install         # installs workspace dependencies (pnpm 12.8.1, pinned by packageManager)
pnpm test            # tests in every TypeScript package
pnpm typecheck       # tsc --noEmit in every TypeScript package
pnpm check:docs      # documentation integrity
```

pnpm is installed per user with `npm install -g pnpm` (Corepack's `enable` needs admin rights to write into the nvm-managed Node folder on this machine). If `pnpm` isn't found in a new shell, add `%APPDATA%
pm` to `PATH`.

## Planned toolchain (installed by P0 tasks)

| Tool | Needed for | Task |
|---|---|---|
| Flutter SDK (stable), JDK 17, Android SDK command-line tools | Mobile app and plugin | FND-T-004 |
| Android Emulator + system image `system-images;android-35;google_apis;x86_64` (+ API 30 for nightly) | Emulator testing | FND-T-008 |
| Cloud macOS: GitHub Actions `macos-*` runners (primary), Codemagic (overflow) | All iOS builds and tests (no local Mac) | FND-T-009 |

### Android Emulator on Windows

1. Install the Android SDK command-line tools, then:
   `sdkmanager "platform-tools" "emulator" "system-images;android-35;google_apis;x86_64"`
2. Acceleration: because Hyper-V/WSL2 is active, the emulator needs **Windows Hypervisor Platform**. Check with `emulator -accel-check`. If it's disabled, the owner enables it once (admin): *Turn Windows features on or off → Windows Hypervisor Platform*, then reboots. Agents must ask the owner rather than attempt elevation.
3. Create the standard AVD (the name is used by scripts and docs):
   `avdmanager create avd -n doro_api35 -k "system-images;android-35;google_apis;x86_64" -d pixel_7`
   Set `hw.camera.back=virtualscene` and `hw.camera.front=emulated` in the AVD `config.ini`.
4. Run headless for tests: `emulator -avd doro_api35 -no-window -no-audio -no-snapshot-save -gpu swiftshader_indirect`
5. The emulator reaches the host's local API and MinIO via `10.0.2.2` (no `adb reverse` needed).

Resource note: 16 GB RAM supports one emulator plus the Docker stack. Don't run two emulators locally.

### iOS without a Mac

- Every iOS build and test runs in the cloud (ADR-0013). Agents push a branch, then run `gh workflow run ios.yml --ref <branch>`, `gh run watch`, and `gh run view --log-failed`.
- Codemagic is the overflow runner. The owner connects the GitHub repo in the Codemagic UI once; after that, `codemagic.yaml` in the repo defines the workflow.
- Simulator camera: none. Debug and test builds use the plugin's synthetic camera source (ADR-0013).

### Planned services (`infrastructure/docker-compose.yml`, FND-T-003)

| Service | Port | Purpose |
|---|---|---|
| postgres | 5432 | Metadata + pg-boss |
| minio | 9000 (S3), 9001 (console) | S3-compatible storage |
| minio-init | — | Creates the bucket, CORS, and lifecycle rule (abort incomplete multipart after 7 days) |

### Planned commands

```sh
docker compose -f infrastructure/docker-compose.yml up -d
pnpm --filter api dev          # API on :3000
pnpm --filter api worker:dev   # worker
pnpm --filter web dev          # web on :5173
cd apps/mobile && flutter run -d emulator-5554
```

### Optional: owner's physical devices (field verification only)

- **Honor X9c:** enable Developer options, then USB debugging. Install the CI debug APK artifact with `adb install`. The phone reaches the local API via `adb reverse tcp:3000 tcp:3000` and `adb reverse tcp:9000 tcp:9000`.
- **iPhone 12 Pro Max:** needs TestFlight, which requires the Apple Developer Program (an owner decision).

## Windows notes

- Keep LF line endings. `.gitattributes` enforces this, and `core.autocrlf=false` is set in the repo.
- Avoid path-length issues: enable long paths (`git config core.longpaths true`) if Gradle complains. The repo path contains a space (`Doro Cam`), so always quote paths in scripts.
- Commands in docs are POSIX. PowerShell equivalents are given where they differ. In PowerShell, run `gh ... --jq` through the Bash tool, because PowerShell splits the quoted jq expressions.
