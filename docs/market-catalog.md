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

An application is classified `high_privilege` exactly when it requests Docker socket access, a host device, or host networking. It must declare the exact acknowledgement `I ACCEPT HIGH PRIVILEGE: <app-id>`. Installation additionally requires that exact text through `--risk-ack`; `--confirm` alone is insufficient. High-privilege applications cannot request managed domain exposure. Revoked entries remain visible but cannot be newly installed.

NAS templates use only `{nas_path}/...` sources and installation requires a safe absolute `--nas-path`. FusionBox does not create, chmod, or otherwise manage the supplied host path.

## Phase-one boundaries

Declarative v1 applications support install, status, and uninstall. Update and retained-data reinstall remain disabled until image-by-image migration and rollback semantics are specified for multi-service applications. The built-in declarative catalog intentionally contains one ordinary example and one revoked high-privilege fixture; future application expansion should add reviewed, digest-pinned entries and targeted lifecycle fixtures rather than weakening the parser.
