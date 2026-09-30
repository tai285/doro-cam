# Doro Cam API + worker image. One image, two commands (docs/architecture/backend.md):
#   node dist/server.js     the HTTP API
#   node dist/worker.js     the pg-boss worker
#   node dist/db/migrate-cli.js   apply database migrations
# Build from the repository root:  docker build -f services/api/Dockerfile -t doro-api .

FROM node:24-alpine AS build
ENV CI=true
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
WORKDIR /app
COPY --from=build /out/node_modules ./node_modules
COPY --from=build /repo/services/api/dist ./dist
COPY --from=build /repo/services/api/migrations ./migrations
COPY --from=build /repo/services/api/package.json ./package.json
USER node
EXPOSE 3000 3001
CMD ["node", "dist/server.js"]
