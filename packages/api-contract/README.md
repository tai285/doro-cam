# api-contract

`openapi.json` is generated from the API route schemas and is the authoritative contract (docs/specs/api.md, ADR-0012).
Regenerate it after changing an endpoint:

```bash
pnpm --filter @doro/api openapi
```

`services/api/test/openapi.test.ts` fails when the committed file is stale.
