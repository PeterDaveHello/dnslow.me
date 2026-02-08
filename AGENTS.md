# Repository Guidelines

## Project Purpose

`dnslow.me` is a privacy-first encrypted DNS stack. This repository manages:

- runtime orchestration (`docker-compose.yml`);
- AdGuard Home policy/config (`adguardhome/conf/AdGuardHome.yaml`);
- Blocky upstream/caching config (`blocky-dns-proxy-config.yml`, mounted as `/app/config.yml` in the container);
- static web assets and Apple profiles (`web/`);
- custom allowlist entries (`whitelist`).

## Architecture Overview

DNS query path is `Client -> AdGuard Home -> Blocky -> public encrypted resolvers`.

- `adguardhome` enforces filtering policy and forwards allowed queries to `blocky`.
- `blocky` distributes traffic across many DoH/DoT upstreams and provides caching.
- `adguardhome` also has `fallback_dns`; during upstream failure it can query public DoH resolvers directly.
- `adguardhome` is the public entrypoint for DNS traffic; `blocky` stays internal to the compose network.
- Blocky config currently includes external Redis at `172.17.0.1:6379` for cache/state sync; this host is environment-specific.
- Redis is optional unless `redis.required: true` is set (Blocky default is `false`).
- Local runtime data lives under `adguardhome/work/` (created on first run; git-ignored).
- TLS key material (host path: `adguardhome/conf/server.crt`, `adguardhome/conf/server.key`; container path: `/opt/adguardhome/conf/`) must stay local and never be committed.

## Core Commands

Use Docker Compose syntax consistently. Prefer `docker compose` (V2); if unavailable, use `docker-compose` (V1 equivalent).

- Validate config: `docker compose config`
- Start services: `docker compose up -d`
- Restart after config edits: `docker compose restart`
- Health status: `docker compose ps`
- Service logs: `docker compose logs --tail=50 adguardhome blocky`
- Live logs (debugging): `docker compose logs -f adguardhome blocky`

## Change Playbooks

### 1) `docker-compose.yml` updates

- Keep image tags pinned (example: `adguard/adguardhome:v0.107.71`).
- Required checks: `docker compose config` then `docker compose up -d`.
- Confirm `docker compose ps` reports expected `running`/`healthy` states.

### 2) `AdGuardHome.yaml` updates

- Keep changes minimal and policy-focused.
- AdGuard Home API/Web UI can overwrite file content; avoid conflicting edits during active UI-driven changes.
- For manual file edits, prefer stopping services first and restarting after changes are complete.
- If upgrading AdGuard image, verify schema/config compatibility in the same PR.
- Required checks: `docker compose restart`, then inspect logs for startup/config errors.

### 3) `blocky-dns-proxy-config.yml` updates

- Keep DoT (`tcp-tls:`) and DoH (`https://`) entries aligned where both are intended.
- Quick consistency scan: `grep -E 'tcp-tls:|https://' blocky-dns-proxy-config.yml` (most providers should appear in both forms; single-protocol providers are acceptable if intentional).
- If Redis sync is not intentionally used, remove the `redis` section to disable external Redis dependency explicitly.
- Required checks: restart stack and inspect recent Blocky logs.

### 4) `whitelist` updates

- Use one domain per line with optional rationale:
  `example.com    # false positive case`
- Add only the minimum exceptions needed to fix a specific false positive.

### 5) `web/` updates

- Keep `web/index.html` static and readable; preserve semantic headings.
- Verify links and profile downloads still resolve correctly.

## Style & Editing Standards

- Text files: UTF-8, LF endings.
- YAML: 2-space indentation, no tabs.
- Preserve existing key ordering unless a tool/export rewrites it.
- Prefer focused diffs over refactors in config-heavy files.

## Operating Principles

- Infrastructure as Code: keep intended runtime behavior represented in versioned config.
- Privacy first: keep logging and data exposure at the minimum needed for operations and debugging.

## Safety Boundaries

### Always

- Keep changes scoped to the requested task.
- Record exact verification commands and results in PR notes.

### Ask First

- Broad filter strategy changes.
- DNS policy behavior changes (for example `blocking_mode`, `upstream_dns`, large filter source changes).
- New runtime dependencies or deployment-scope changes.

### Never

- Commit secrets, certificates, keys, or runtime-generated data.
- Modify unrelated files to “clean up” outside the request.
- Hide risky behavior changes without explicit PR notes.

## Commit & Pull Request Guidelines

- Use concise imperative commit subjects:
  `Update spx01/blocky Docker tag to v0.28.2`
- Keep one concern per commit (version bump, config behavior, whitelist entry, or web content).
- PRs should include:
  - what changed and why;
  - validation commands and outcomes;
  - user impact, especially DNS/filtering behavior changes;
  - linked issue (if applicable);
  - screenshots only for visible `web/` UI/content updates.
