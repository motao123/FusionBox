# Managed application catalogs

FusionBox's managed market accepts a data-only JSON catalog. The v1 contract is published at `src/lib/market-catalog.schema.v1.json`; the stricter runtime parser is `src/lib/market_catalog.py`. Catalog data is parsed as JSON and is never sourced, evaluated, imported, or executed as code.

## Loading and pinning

The built-in catalog is always available. A remote catalog must use HTTPS and must be pinned with `--catalog-sha256`, `--catalog-revision`, or both:

```sh
fusionbox market managed catalog \
  --catalog-url https://example.invalid/catalog.json \
  --catalog-sha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

A validated remote response is cached with an atomic replace under the private Compose registry directory. A later fetch failure uses only a cache whose URL and pins match the request; otherwise FusionBox falls back to the built-in catalog and reports that source. Catalogs are limited to 1 MiB, reject unknown fields, and require digest-pinned container images.

The selected catalog arguments must be supplied on each invocation that needs a remote application ID. Installed records retain the exact validated application object, its SHA256, catalog identity, revision, and source, so status and uninstall do not silently change when a remote catalog changes or disappears.

## Security model

All declared bridge-mode ports render as `127.0.0.1` bindings, including UDP. The v1 model supports multiple services, named volumes, host binds, NAS path templates, devices, bridge or host networking, and Docker socket access. Ordinary services receive capability dropping and `no-new-privileges` defaults.

In a catalog `network_mode: bridge` means **the application's own private Compose network**, not Docker's global default bridge: services resolve each other by service ID (`db`, `api`, …). Emitting the literal `bridge` would place every service on the host-global bridge, where names do not resolve — a multi-container application could not reach its own database. Only `network_mode: host` is passed through verbatim, and host-network services may not publish ports.

Each declared capability is allowlisted rather than forwarded to Docker unchecked:

| Field | Contract |
|---|---|
| `depends_on` | Service IDs declared in the same application; no self-reference, no duplicates, no cycles. Rendered as `condition: service_healthy` (every service must declare a healthcheck). |
| `shm_size` | `<n>m`; verified against the running container's real `ShmSize`. |
| `sysctls` | Namespaced keys only, and only the ones this Docker accepts **without `--privileged`** (probed on Docker 29.8.1): `net.core.somaxconn`, `net.ipv4.ip_local_port_range`, `net.ipv4.tcp_syncookies`. `vm.max_map_count` and `fs.file-max` are refused — they need privileged, which the managed model never grants, so Elasticsearch-based stacks cannot be hosted here. |
| `tmpfs` | Absolute paths, no traversal. |
| `read_only` | Boolean; the container's root filesystem is read-only. |
| `entrypoint` | Non-empty argument list. A shell-form entrypoint (`… -c`) combined with a multi-argument `command` is rejected: Docker concatenates both into one argv, so `["/bin/sh","-c"] + ["sleep","600"]` really runs `sleep` with `$0=600` and fails at runtime. Real deployment surfaced this. |

An application is classified `high_privilege` exactly when it requests Docker socket access, a host device, or host networking. It must declare the exact acknowledgement `I ACCEPT HIGH PRIVILEGE: <app-id>`. Installation additionally requires that exact text through `--risk-ack`; `--confirm` alone is insufficient. High-privilege applications cannot request managed domain exposure. Revoked entries remain visible but cannot be newly installed.

NAS templates use only `{nas_path}/...` sources and installation requires a safe absolute `--nas-path`. FusionBox does not create, chmod, or otherwise manage the supplied host path.

## Multi-container lifecycle

Declarative applications support `install`, `status`, `update`, `reinstall --reuse-data` and `uninstall`.

- **install** — refuses an existing registry, Compose file, container name or named volume; pulls every digest-pinned image; brings the stack up with `--wait` so `depends_on` health conditions are actually honored.
- **update** — takes the current catalog entry for the same application and refuses any **structural** change: service set, storage, published ports, network mode, binds, devices, socket. Those move data or change reachability, so they require uninstall then install. Image replacement is explicit: `--service-image <service>=<image@sha256:…>`. When nothing changes it is a no-op. Otherwise it is one transaction: pull first, write a private recovery journal, swap images, re-up, health-gate; on failure it restores the previous snapshot and brings the old images back, and only removes the journal once the application is healthy again. If both the update and the rollback fail, the state becomes `recovery-required` and the journal is retained — later mutations are refused until it is resolved by hand.
- **reinstall --reuse-data** — only from `uninstalled`, only with no containers, and only when every declared named volume still exists; it never invents a replacement volume.
- **uninstall** — removes containers, retains named volumes, the registry and the configuration.

`resources()` revalidates every declared capability against the running containers (network mode, shared memory, sysctls, root-filesystem mode, tmpfs, entrypoint, mounts, ownership labels) before any stop/remove/recreate, so drift is rejected instead of silently accepted.

## Catalog contents

The built-in declarative catalog holds reviewed, digest-pinned entries: an ordinary single-service example (`ntfy-v1`), a revoked high-privilege fixture (`docker-admin-example`), and `umami` — a real two-service application (application + PostgreSQL) whose full lifecycle is exercised by `tests/acceptance/market_multicontainer.sh` on a real Docker host. Expansion should add reviewed, digest-pinned entries and targeted lifecycle fixtures rather than weakening the parser.

`vm.max_map_count` is deliberately absent from the sysctl allowlist, which is why Elasticsearch-based stacks (for example RAGFlow) cannot be hosted under this model without `high_privilege`; that limitation is recorded in `docs/roadmap.md`.
