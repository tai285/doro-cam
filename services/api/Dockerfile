# Doro Cam API + worker image. One image, two commands (docs/architecture/backend.md):
#   node dist/server.js     the HTTP API
#   node dist/worker.js     the pg-boss worker
#   node dist/db/migrate-cli.js   apply database migrations
# Build from the repository root:  docker build -f services/api/Dockerfile -t doro-api .

FROM node:24-alpine AS build
ENV CI=true
# pnpm refuses dependencies released less than this many minutes ago (default policy: one day). A build made right after a
# dependency release can pass --build-arg MIN_RELEASE_AGE=0; the lockfile pins exact versions and integrity hashes either way.
ARG MIN_RELEASE_AGE=1440
ENV pnpm_config_minimum_release_age=$MIN_RELEASE_AGE
RUN npm install --global pnpm@12.8.1
WORKDIR /repo
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY services/api/package.json services/api/
COPY tools/docs-check/package.json tools/docs-check/
COPY tools/local-infra/package.json tools/local-infra/
RUN pnpm install --frozen-lockfile --filter @doro/api...
COPY services/api services/api
RUN pnpm --filter @doro/api build
RUN pnpm --filter @doro/api deploy --prod --legacy /out

FROM node:24-alpine
ENV NODE_ENV=production
# ffmpeg/ffprobe: the worker makes web renditions, posters and metadata-free copies of clips (docs/architecture/media-pipeline.md).
RUN apk add --no-cache ffmpeg
WORKDIR /app
COPY --from=build /out/node_modules ./node_modules
COPY --from=build /repo/services/api/dist ./dist
COPY --from=build /repo/services/api/migrations ./migrations
COPY --from=build /repo/services/api/package.json ./package.json
# The worker needs a writable temp directory for transcodes and archives.
ENV TMPDIR=/tmp
USER node
EXPOSE 3000 3001
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s CMD wget -qO- http://127.0.0.1:${PORT:-3000}/healthz >/dev/null 2>&1 || exit 1
CMD ["node", "dist/server.js"]
