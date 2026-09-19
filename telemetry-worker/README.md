# FusionBox telemetry Worker

Phase-one anonymous telemetry backend. It accepts a fixed event schema, HMACs installation IDs and request sources with a Worker secret, and stores only daily aggregates plus first/last-seen dates.

## Local checks

```sh
npm ci
npm test
npm run typecheck
```

For local Worker/D1 testing, create the local database and apply the migration:

```sh
npx wrangler d1 migrations apply fusionbox-telemetry --local
npx wrangler dev --var TELEMETRY_HMAC_KEY:local-development-key-at-least-32-bytes
```

## Request schema

`POST /v1/event` requires `Content-Type: application/json`, a body no larger than 4096 bytes, and exactly these fields:

```json
{
  "schema_version": 1,
  "event": "install",
  "installation_id": "0123456789abcdef0123456789abcdef",
  "version": "1.24.0",
  "os": "debian",
  "arch": "x86_64"
}
```

Allowed events are `install`, `update`, `uninstall`, and `heartbeat`. Allowed OS values are `debian`, `ubuntu`, `centos`, `rocky`, `almalinux`, `fedora`, `arch`, and `other`. Allowed architectures are `x86_64`, `aarch64`, `armv7l`, and `other`.

Public endpoints are `GET /v1/public/summary` and `GET /v1/public/badge`. Responses permit cross-origin reads and are cached for five minutes.

## Deployment

1. Create a D1 database with `npx wrangler d1 create fusionbox-telemetry`.
2. Put its returned ID in `wrangler.jsonc`; do not commit account credentials.
3. Create a random secret of at least 32 characters and set it with `npx wrangler secret put TELEMETRY_HMAC_KEY`.
4. Run `npx wrangler d1 migrations apply fusionbox-telemetry --remote`.
5. Run the checks above, then deploy explicitly with `npm run deploy`.

The fixed-window D1 limiter caps each installation at 30 and each HMACed source address at 120 accepted attempts per UTC hour. It protects this low-volume endpoint from ordinary abuse, but D1 is not a dedicated edge rate-limiting product: distributed bursts, retries between the two counters, and database availability can affect precision. Use Cloudflare Rate Limiting or a Durable Object before treating it as a hard security or billing boundary.
