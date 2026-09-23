<div align="center">

# FusionBox

**One command to take over an entire Linux server**

9 modules · 70+ software market · managed application lifecycle · every step can be rolled back

[![version](https://img.shields.io/badge/version-1.43.0-blue)](https://github.com/motao123/FusionBox/releases)
[![CI](https://github.com/motao123/FusionBox/actions/workflows/release.yml/badge.svg)](https://github.com/motao123/FusionBox/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![platform](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20CentOS%20%7C%20Alpine-orange)](#appendix)
[![GitHub release downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fmotao123.github.io%2FFusionBox%2Fgenerated%2Fgithub-downloads-shield.json)](https://github.com/motao123/FusionBox/releases)
[![GitHub Stars](https://img.shields.io/github/stars/motao123/FusionBox)](https://github.com/motao123/FusionBox/stargazers)

English | [简体中文](README.md)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/motao123/FusionBox/main/install.sh)
```

<sub>Debian · Ubuntu · CentOS · RHEL · Fedora · Alpine | amd64 / arm64 | requires root | Mostly Bash, with controlled Python helpers</sub>

</div>

---

## Contents

| | |
|---|---|
| [Why use it](#why-use-it) | [Managed application market](#managed-application-market) |
| [Get started in 30 seconds](#get-started-in-30-seconds) | [Real-machine verification](#real-machine-verification) |
| [Capability map](#capability-map) | [Command reference](#command-reference) |
| [Recent changes](#recent-changes) | [Honest boundaries](#honest-boundaries) |

---

## Why Use It

One-click scripts are everywhere; what makes FusionBox different is **that it does not pretend to have verified everything**:

- **Every step can be rolled back.** A config change is staged first, then backed up, then verified after the write; on failure it rolls back automatically - no machine left "changed halfway".
- **A typo will not lock you into a menu.** An unknown subcommand prints an actionable next step and exits with code 2; the menu only appears on an interactive terminal, so scripts and CI never hang.
- **The managed application market is data-driven, not a pile of loose docker run commands.** Pinned image digests, localhost-only publishing, memory/CPU/PID limits, real health checks, disk pre-flight; the whole install / update / backup / uninstall / reinstall flow is testable.
- **Only configuration that is actually read gets declared.** Every key in `config.yaml` maps to a real read site, so you never "flip a switch that does nothing".
- **Verification conclusions are filed in tiers.** Locally mocked / isolated fixture / verified on real hardware / unverified - four separate labels, and no "it should work" promises.

---

## Get Started in 30 Seconds

```bash
# 1. Install (missing dependencies are filled in automatically)
bash <(curl -fsSL https://raw.githubusercontent.com/motao123/FusionBox/main/install.sh)

# 2. Enter the main menu, or call a module command directly
fusionbox
```

Three commands where the difference is noticeable right away:

```bash
fusionbox system tools                # System toolbox (SSH / firewall / disk / user management / hardening wizard)
fusionbox market managed catalog      # Managed application market (templates read dynamically, one-click deploy/backup/uninstall)
fusionbox network bench               # VPS benchmark matrix (YABS / Bench / return-path routing, etc.)
```

The help system is read-only, **you can read it without root**; `fusionbox help system` and `fusionbox system help` produce body text that is byte-for-byte identical:

```bash
fusionbox lang en                     # Switch the UI language (zh_CN / en / auto)
fusionbox help                        # Top-level help: 9 modules + global commands
fusionbox help system                 # Detailed module help (command list + live host status line)
fusionbox system help                 # Equivalent spelling, same body text
fusionbox help sys                    # Aliases work too (p/net/w/tools/m/ws/cl ...)
fusionbox panels docker help          # Sub-dispatch also answers help
```

> The trailing "host status" line is a live read-only probe of the machine (whether Docker answers, which components are installed), capped at 3 seconds;
> on the same machine that line may legitimately differ between two runs, the help body text will not.

---

## Capability Map

| Module | Command | In one line |
|------|------|------|
| Proxy management | `fusionbox proxy` | Multi-backend proxy (Xray / v2ray / 233boy sing-box / Clash.Meta) |
| System management | `fusionbox system` | BBR, benchmarks, backups, SSH, firewall, cron, disk, timezone, trash, rescue guidance |
| Network tools | `fusionbox network` | IP lookup, streaming detection, speed tests, DNS, traceroute, port checks |
| Web deployment | `fusionbox web` | LNMP, SSL, 17 application deployments, reverse proxy, L4 forwarding, site backups |
| Panel tools | `fusionbox panels` | Full Docker management, 宝塔 / Aapanel / FRP / Aria2 / 哪吒监控 |
| Application market | `fusionbox market` | 70+ one-click installs (10 categories) + managed template lifecycle |
| WARP management | `fusionbox warp` | Cloudflare WARP install, Proxy mode, streaming unlock |
| Background workspace | `fusionbox workspace` | Numbered workspaces w1-w10 (tmux / screen auto-selected) |
| Cluster control | `fusionbox cluster` | Multi-machine batch management, game servers, OCI read-only identification, k command, Chinese quick-reference sheet |

<details>
<summary><strong>Expand: detailed capabilities of each module</strong></summary>

| Module | Detailed capabilities |
|---|---|
| `proxy` | Xray-core / v2ray-core / **233boy sing-box (recommended)** / Clash.Meta; protocols VLESS (incl. Reality), VMess, Trojan, Hysteria2, TUIC, Shadowsocks, SOCKS5; transports TCP / WebSocket / gRPC / HTTPUpgrade; automatic merge of multiple configs, share-link generation, per-backend validation of protocol combinations |
| `system` | System info, BBR (incl. BBR2 / BBRplus / modded / Lotserver / xanmod), CPU and disk benchmarks, network speed test, real-time monitoring, backup and restore, system cleanup; the toolbox adds SSH keys, firewall (UFW/iptables/Fail2Ban), cron, disk partitioning and mounting, one-click switching across 29 cities + custom IANA + NTP, trash, file manager, rsync sync jobs |
| `network` | IPv4/IPv6 and ISP info, Netflix/YouTube/ChatGPT/TikTok/Disney+/Bilibili unlock detection, upload/download speed tests, resolution comparison across multiple DNS servers, Traceroute, port probing, network interface management |
| `web` | One-click LNMP / LAMP install, site creation and Nginx virtual hosts, automatic certbot issuance (both validation routes supported: local Pebble and LE staging), databases and user privileges, 17 built-in application deployments, reverse proxy and load balancing, Stream L4 forwarding, site cloning, site data backups, tuning presets and brotli |
| `panels` | Docker install and full management (containers/images/Compose/networks/volumes/cleanup/backup and migration/daemon.json), container port blocking (DOCKER-USER), 宝塔 / Aapanel / X-UI, Aria2 / Rclone / FRP / 哪吒监控 |
| `market` | 70+ applications, 10 categories; the `managed` subcommand is a data-driven Compose lifecycle (next section) |
| `warp` | WARP install and uninstall, Proxy mode (does not drop SSH), IP and unlock status detection, outbound configuration examples |
| `workspace` | Numbered workspaces w1-w10, tmux / screen auto-selection, supports command injection |
| `cluster` | Add and remove nodes, batch execution, file sync, SSH outbound favorites; game servers (Minecraft Java/Bedrock, Terraria, Palworld); OCI read-only identification and keep-alive status; `k` command shortcuts |

</details>

---

## Managed Application Market

`fusionbox market managed` is a data-driven Compose lifecycle: digest-pinned images, localhost publishing,
memory/CPU/PID limits, real health checks, disk pre-flight, and install / update / backup / uninstall / reinstall
are **verified item by item on real hardware**.

| Template | Category | localhost port | In one line |
|------|------|------|------|
| nginx | Web serving | 8080 | Static site (read-only content volume, domain mapping supported) |
| ntfy | Notification service | 8081 | Local notifications (SQLite cache, no authentication) |
| uptime-kuma | Monitoring panel | 8082 | Uptime checks / status pages |
| ddns-go | DDNS | 8083 | Dynamic DNS |
| new-api | AI gateway | 8084 | LLM API gateway and billing (no authentication on first start, set an admin first) |
| lobe-chat | AI chat | 8085 | Aggregates ChatGPT / Claude / Gemini / Ollama |
| open-webui | AI chat | 8086 | Self-hosted frontend for Ollama / OpenAI |
| n8n | Automation | 8087 | Workflow automation |
| openlist | Netdisk / WebDAV | 8088 | Multi-storage file list (Alist fork) |
| navidrome | Music streaming | 8089 | data + music dual volume (music read-only) |
| umami | Web analytics | 8090 | app + PostgreSQL dual service (starts only after db is healthy; reinstall onto existing data and per-service image swap supported) |

> The template list follows the actual output of `fusionbox market managed catalog`; for the declarative catalog and the high-privilege boundary see [docs/market-catalog.md](docs/market-catalog.md).

---

## Real-Machine Verification

Run from scratch on a **freshly installed Ubuntu 22.04** (Docker CE 29.8.1 + Compose v5.5.1, no legacy environment at all):

| Layer | Item | Result |
|---|---|---|
| Static gate | `bash tests/run_checks.sh` | **193 / 193** (passes both as root and as non-root) |
| Full suite | `bash tests/comprehensive_test.sh` | bash **229** items + Python **764** items (34 modules), zero failures |
| Real self-install | official `install.sh` | Release asset download + SHA256 check -> install -> `fusionbox help` / module help / non-root refusal / unknown subcommand exit code 2, all as expected |
| Real-machine acceptance | 9 scripts in `tests/acceptance/` | **9 / 9 passed** (see table below) |

| Real-machine acceptance script | Coverage | Count |
|---|---|---|
| `container_lifecycle.sh` | Full container lifecycle | 17 / 17 |
| `market_app_expansion.sh` | Managed template install -> HTTP -> uninstall keeps volumes -> reinstall reusing data | 11 / 11 |
| `market_multicontainer.sh` | Multi-container (umami + PostgreSQL): dependency order, image swap, rollback, data reuse | 34 / 34 |
| `two_host.sh` | Two-host orchestration, rsync, disaster-recovery transfer (the second host is played by a container) | 29 / 29 |
| `openssh_switch.sh` | OpenSSH candidate switch and rollback (a container plays the production role, asserts the host config is unchanged) | 32 / 32 |
| `acme_pebble.sh` | Local Pebble: issue -> managed TLS assembly -> real renewal -> rollback on failure | 25 / 25 |
| `acme_staging.sh` | Let's Encrypt staging: real DNS + real HTTP-01 issuance | 16 / 16 |
| `netopt_sysctl.sh` | Real kernel network parameter changes + snapshot restore with zero drift | 11 / 11 |
| `cloudflare_guard.sh` | CF load-adaptive shield on + API IP ban (minimal-privilege Token) | 21 / 21 |

> The table above is the verification conclusion for the local test assets; `tests/` is not committed to the repo, full regression runs locally and on the verification server.

CI only does static checks (see below), and both repos (GitHub / CNB) use the same pipeline: `syntax` (script syntax + Python artifacts + i18n bilingual contract audit + version consistency across five places) -> `release` (tag-triggered only, produces a verified release package). **Test assets are not committed**: `tests/` lives only locally and on the verification server (`.gitignore` blocks it and `.gitattributes` sets `export-ignore`, a double lock; the release package never contains tests anyway), full regression runs locally and on real hardware.

---

## Recent Changes

> Current version **v1.43.0** | full history in [docs/CHANGELOG.md](docs/CHANGELOG.md)

<!-- Release slot: when the next version ships, replace this section with a 3-5 line summary of the new version; move the replaced full version paragraphs verbatim to the top of docs/CHANGELOG.md (keeping reverse chronological order). -->

- **Bilingual support closed out (second batch: module layer 100% bilingual)**: all 9 modules now go through the language packs, **3247 keys** (Chinese and English equal key for key) - in Chinese mode the output is **byte-for-byte identical** to v1.42.0 (diff=0 across 30 read-only scenarios), and in English mode the help, menus and entry output contain **0 Chinese characters**
- **The extractor covers every user-facing output site**: besides the output functions it also handles interactive arguments such as `read -p`/`confirm`/`select_option`, the `_log_write`/`_require_*` guards, variable assignments (status labels), and the menus and data tables (74 application-catalog entries, 13 benchmark-matrix rows, 29 timezone presets)
- **Zero unextracted strings left in the whole repo**: section 22 of `run_checks.sh` is upgraded to repository-wide enforcement, so a new Chinese literal output site turns the gate red immediately
- **Measured numbers**: on real hardware (Ubuntu 22.04) the gate is **193/193** (root and non-root), the full suite is bash **229** items + Python **764** items (34 modules) with zero failures; the Chinese comparison matches v1.42.0, the English output has zero Chinese
- **The repo keeps only shipping artifacts**: `tests/` is no longer committed (the full tests stay locally and on the verification server), CI is narrowed to static checks - syntax / Python artifacts / i18n bilingual contract audit / version consistency across five places; release packaging unchanged


- **B4 closed out (the Cloudflare half)**: minimal-privilege API Token verified with real credentials - `fusionbox-cf-guard` load-adaptive shield 8/8 on real hardware (security_level really flips to under_attack, falls back to the baseline when load drops, idempotent), `fusionbox-cf-ban` ban / unban / idempotency all pass on real hardware; new real-machine acceptance script `tests/acceptance/cloudflare_guard.sh` (21/21, restores the security_level baseline and cleans up test rules on every exit path)
- **Fixed by measuring on real hardware**: the CF API returns pretty JSON (space after the colon in `"success": true`), so the compact-format assertions in cf-ban/cf-guard were all relaxed to tolerate whitespace - static tests could not catch this, it showed up on the first real run
- **New feature**: Cloudflare integration config accepts a pasted Global API Key - it lists the Zones of the account, mints on the spot a minimal-privilege Token scoped to the selected Zone only (Zone Settings + Firewall Services, 14 day validity), and the Global Key itself is never written to disk; end-to-end verified with a real Key (mint -> verify active -> read security_level)
- **The Telegram half stands as before**: real send verification of `system notify` still needs a bot token, and the explicit refusal when credentials are missing is unchanged

---

## Command Reference

Grouped by module and collapsed below, all commands and descriptions kept verbatim (expand to view):

<details>
<summary><strong>Quick reference for commands used across modules</strong></summary>

```bash
fusionbox system users           # User management (list/add/del/sudo/unsudo/passwd)
fusionbox system hardening       # SSH hardening: create a key-based user and tighten root login
fusionbox system fail2ban        # Fail2Ban panel (status/unban/logs/params/uninstall)
fusionbox system env             # Environment variable management (list/show/check/edit)
fusionbox system rsync           # rsync sync jobs (add/list/run/cron)
fusionbox system file            # File manager (ls/cat/cp/mv/del/tar/send)
fusionbox panels docker port-block  # Container port blocking (DOCKER-USER, list/add/del)
fusionbox panels docker uninstall   # One-click Docker uninstall (YES gate)
fusionbox workspace work            # Numbered workspaces (tmux w1-w10, command injection)
fusionbox cluster sshout            # SSH outbound favorites (add/list/rm/connect)
fusionbox market managed install uptime-kuma / ddns-go   # Managed template expansion
fusionbox market managed install new-api                 # Managed template for an LLM API gateway
fusionbox market managed install lobe-chat/open-webui/n8n/openlist/navidrome  # Five new templates
fusionbox web tune                  # Tuning presets (standard/high/restore)
fusionbox web brotli                # brotli compression switch
fusionbox web clone                 # Site cloning (files + config + optional WP database)
fusionbox web uninstall-lnmp        # Uninstall LNMP (YES gate + config backup)
fusionbox update --cron on|off      # Automatic update switch (weekly)
```

</details>

<details>
<summary><strong>1. Proxy management (<code>fusionbox proxy</code>)</strong></summary>

Multi-backend generic proxy management with one-click install and configuration:

- **Supported backends**: Xray-core, v2ray-core, **233boy/sing-box (recommended)**, Clash.Meta
- **Supported protocols**: VLESS (incl. Reality), VMess, Trojan, Hysteria2, TUIC, Shadowsocks, SOCKS5
- **Transports**: TCP, WebSocket, gRPC, HTTPUpgrade
- **Config management**: automatic merge of multiple configs, share-link generation
- **Protocol fit**: FusionBox's own config generation targets the Xray/v2ray cores; the sing-box backend is handed to the community best-practice [233boy/sing-box](https://github.com/233boy/sing-box) script (it creates a REALITY config during install and supports all protocols such as TUIC/Hysteria2); when you add a config, protocol combinations unsupported by the backend are validated and rejected

```bash
fusionbox proxy install          # Install a proxy core (pick 1 of 4, sing-box goes through the 233boy script)
fusionbox proxy add              # Add a proxy config (protocol validated against the backend)
fusionbox proxy sb               # Enter the 233boy sing-box interactive main menu
fusionbox proxy sb add           # Pass-through: add a sing-box config (same as sing-box add)
fusionbox proxy sb url           # Pass-through: generate a share link
fusionbox proxy list             # List all configs
fusionbox proxy start            # Start the proxy service
fusionbox proxy stop             # Stop the proxy service
fusionbox proxy restart          # Restart the proxy service
fusionbox proxy status           # Show proxy status (incl. 233boy sing-box instances)
fusionbox proxy url <名称>       # Generate a share link
fusionbox proxy del <名称>       # Delete a config
fusionbox proxy bbr              # Enable BBR acceleration
```

</details>

<details>
<summary><strong>2. System management (<code>fusionbox system</code>)</strong></summary>

Comprehensive system operations tooling:

**Basic functions:**
- **System info**: detailed CPU, memory, disk, network, kernel and virtualization info
- **BBR management**: full BBR/BBR2/BBRplus/modded/Lotserver/xanmod management
- **Performance tests**: CPU benchmark, disk I/O test, network speed test
- **Real-time monitoring**: CPU/memory/disk/network live monitoring panel
- **Backup and restore**: one-click backup and restore of system configuration
- **System cleanup**: package cache, logs, temp files, Docker garbage

**System tools (`fusionbox system tools`):**
- **SSH key management**: add/generate/delete keys, disable password login
- **Firewall management**: UFW/iptables, port switching, IP bans, Fail2Ban
- **Cron management**: add/remove/edit cron entries, automatic backup/cleanup
- **Disk management**: partition/format/mount/expand/large-file scan/directory sizes
- **Timezone management**: one-click switching across 29 common cities (Asia/Europe/Americas/Oceania/Africa) + custom IANA timezones + NTP sync
- **Trash management**: safe delete/restore/empty

```bash
fusionbox system info            # Show system information
fusionbox system bbr             # BBR management
fusionbox system benchmark       # Run performance tests
fusionbox system monitor         # Real-time system monitoring
fusionbox system backup          # Back up system configuration
fusionbox system update          # Update system packages
fusionbox system clean           # System cleanup
fusionbox system tools           # System tools submenu
fusionbox system sshkey          # SSH key management
fusionbox system firewall        # Firewall management
fusionbox system cron            # Cron job management
fusionbox system disk            # Disk management
fusionbox system timezone        # Timezone management
fusionbox system trash           # Trash management
```

</details>

<details>
<summary><strong>3. Network tools (<code>fusionbox network</code>)</strong></summary>

Practical network diagnosis and testing tools:

- **IP lookup**: IPv4/IPv6 addresses, geolocation, ISP information
- **Streaming detection**: Netflix, YouTube, ChatGPT, TikTok, Disney+, Bilibili and more
- **Speed test**: download/upload speed test
- **DNS test**: resolution speed compared across multiple DNS servers
- **Traceroute**: path analysis
- **Port check**: remote port open-state check
- **Ping test**: connectivity test

```bash
fusionbox network ip             # Look up the IP address
fusionbox network streaming      # Streaming unlock detection
fusionbox network speedtest      # Network speed test
fusionbox network nic            # Network interface management (list/info/up/down)
fusionbox network dns            # DNS resolution test
fusionbox network trace <host>   # Traceroute
fusionbox network ping <host>    # Ping test
fusionbox network port <ip> <端口> # Port check
```

</details>

<details>
<summary><strong>4. Web deployment (<code>fusionbox web</code>)</strong></summary>

One-click build of a web runtime environment and application deployment:

**Basic environment:**
- **LNMP/LAMP**: Nginx/Apache + MySQL/MariaDB + PHP one-click install
- **Site management**: quick site creation, Nginx virtual host configuration
- **SSL certificates**: Certbot automatic Let's Encrypt certificate issuance
- **Database management**: MySQL/MariaDB create database, create user, manage privileges

**LDNMP application one-click deployment (`fusionbox web deploy`):**

| Category | Applications |
|------|------|
| Content management | WordPress, Typecho, Halo, Discuz! Q |
| Netdisk and files | KodExplorer, Nextcloud, Alist |
| Video and media | AppleCMS, Emby, Jellyfin |
| Forums and communities | Flarum, LinkStack |
| Tools and services | Bitwarden, Uptime Kuma, IT-Tools, Memos, Vaultwarden |

**Reverse proxy (`fusionbox web proxy`):**
- HTTP reverse proxy
- HTTPS reverse proxy (automatic SSL)
- Load balancing (multiple backends)

**Stream L4 proxy (`fusionbox web stream`):**
- TCP/UDP port forwarding

**Site data management (`fusionbox web sitedata`):**
- One-click backup/restore of site data
- Local config supports scheduled archiving; the legacy remote full-job creation entry is disabled, existing jobs need manual review

```bash
fusionbox web lnmp               # Install the LNMP environment
fusionbox web site               # Create a site
fusionbox web ssl                # Request an SSL certificate
fusionbox web deploy             # LDNMP application deployment
fusionbox web wordpress          # Quick WordPress deployment
fusionbox web proxy              # Reverse proxy management
fusionbox web stream             # Stream L4 port forwarding
fusionbox web sitedata           # Site data management
```

</details>

<details>
<summary><strong>5. Panels and tools (<code>fusionbox panels</code>)</strong></summary>

Server panels and common tool management:

**Full Docker management (`fusionbox panels docker`):**
- Docker install entry; a complete Docker uninstall is not implemented yet
- Container management (start/stop/restart/delete/logs/terminal/resource usage)
- Image management, Docker Compose project management
- The legacy container port switch is disabled (DNAT mapping missing); the IPv6 network config entry is kept
- daemon.json editing (registry mirrors/log limits/DNS)
- Backup/migrate/restore (containers/images/Compose projects)
- Network management / volume management / garbage cleanup

**Server panels:** 宝塔, Aapanel, X-UI one-click install

**Practical tools:** Aria2, Rclone, FRP intranet penetration, 哪吒监控

```bash
fusionbox panels docker          # Full Docker management
fusionbox panels bt              # Install the 宝塔 panel
fusionbox panels frp             # Install FRP intranet penetration
fusionbox panels aria2           # Install Aria2
fusionbox panels rclone          # Configure Rclone
fusionbox panels nezha           # Install 哪吒监控
```

</details>

<details>
<summary><strong>6. Application market (<code>fusionbox market</code>)</strong></summary>

70+ common applications with one-click install across ten categories (counts follow the actual output of `fusionbox market list`):

| Category | Applications |
|------|------|
| Development tools | Git, Python3, Node.js, Go, Rust, Redis, Memcached, SQLite |
| Network tools | Wget, Curl, Netcat, Socat, MTR, Iperf3, Nmap, Speedtest, FRP, Rclone |
| System tools | Htop, Btop, Glances, Nano, Vim, Unzip, Zip, Fail2Ban, UFW, Certbot, rsync, cron, supervisor, Prometheus |
| Web services | Nginx, Apache, Caddy, PHP, MySQL, PostgreSQL, phpMyAdmin, WordPress |
| Proxy tools | Shadowsocks, V2ray, Xray, HAProxy |
| Media tools | FFmpeg, ImageMagick, ExifTool |
| Container related | Docker CE, Docker Compose, Portainer, cAdvisor |
| Monitoring tools | Netdata, Glances, Bashtop, Neofetch, Fastfetch |
| Security tools | ClamAV, Rkhunter, Lynis, Unattended-upgrades |
| Utility tools | Aria2, FileBrowser, Gost, Warp, 7zip, Tmux, JQ, yq, Tree, Lsof, Strace, Tcpdump |

```bash
fusionbox market list            # List all applications
fusionbox market search <关键词> # Search applications
fusionbox market install <应用>  # Install an application
fusionbox market remove <应用>   # Remove an application
fusionbox market category        # Browse by category
```

</details>

<details>
<summary><strong>7. WARP management (<code>fusionbox warp</code>)</strong></summary>

Cloudflare WARP management, used to unlock streaming via proxied outbound traffic:

- **Safe mode**: Proxy mode (SOCKS5 proxy) by default, it does not drop your SSH session
- **Install/uninstall**: one-click install of the Cloudflare WARP client
- **IP check**: show the original IP and the WARP IP
- **Streaming unlock**: detect the WARP unlock status
- **Proxy config**: Xray/sing-box outbound configuration examples

```bash
fusionbox warp install           # Install WARP
fusionbox warp on                # Turn WARP on (Proxy mode)
fusionbox warp off               # Turn WARP off
fusionbox warp status            # Show WARP status
fusionbox warp ip                # Show IP / streaming unlock
fusionbox warp proxy             # Proxy configuration notes
```

</details>

<details>
<summary><strong>8. Background workspace (<code>fusionbox workspace</code>)</strong></summary>

Terminal session management:

- **Screen management**: create/list/attach/kill screen sessions
- **Tmux management**: create/list/attach/kill tmux sessions

```bash
fusionbox workspace screen       # Screen management
fusionbox workspace tmux         # Tmux management
fusionbox workspace list         # List all background sessions
```

</details>

<details>
<summary><strong>9. Cluster control and tools (<code>fusionbox cluster</code>)</strong></summary>

Multi-server management and practical tools:

**Cluster management:** add/remove nodes, run commands in batches, sync files

**Game servers (`fusionbox cluster game`):**
- Minecraft Java Edition (Paper), Minecraft Bedrock Edition
- Terraria, Palworld

**Oracle Cloud (`fusionbox cluster oracle`):** OCI read-only identification, managed/legacy keep-alive status check; the lookbusy load install still awaits a pinned image and isolated acceptance

**k command shortcuts (`fusionbox cluster kcmd`):**
```bash
k=fusionbox  ks=system  kb=bbr  kn=network
kw=web  kp=proxy  kd=docker  km=market
```

```bash
fusionbox cluster add            # Add a cluster node
fusionbox cluster exec <cmd>     # Run a command in batches
fusionbox cluster sync           # Sync files to the cluster
fusionbox cluster game           # Game server deployment
fusionbox cluster oracle detect  # OCI read-only identification
fusionbox cluster oracle status  # Managed/legacy keep-alive status
fusionbox cluster kcmd           # Configure the k command shortcuts
```

</details>

---

## Honest Boundaries

- Test conclusions are strictly split into four tiers: **locally mocked / isolated fixture / verified on real hardware / unverified**, and release notes ship the precise scope with each version
- Current real-machine standing (v1.43.0, fresh Ubuntu 22.04): quick gate **193/193** (run twice, as root and as non-root), full suite bash **229** items + Python **764** items (34 modules) with zero failures, all 9 real-machine acceptance scripts passed
- **Credential-dependent items already closed out**: Cloudflare integration (v1.41.0, minimal-privilege Token verified on real hardware), both ACME issuance routes (v1.39.0, local Pebble + Let's Encrypt staging with real HTTP-01)
- **Still needs real conditions before it can be verified**: Telegram delivery (needs a bot token), real OCI instances (the Oracle trio), the real power-off branch; OCI G32 has only completed read-only identification, and lookbusy load, oci-helper (G33) and root/IPv6 (G34) are not implemented
- The per-application verification scope of managed apps follows each template's own documentation; gaps and to-dos are reconciled item by item in the implementation tracking document
- Anonymous usage statistics are **off by default**, and you can opt in explicitly on the first interactive install; only a random install identifier, the version, coarse system/architecture information and fixed events are sent, see [the privacy note](docs/privacy.md)
- The statistics Worker is deployed and aggregates through Cloudflare D1; Pages shows the de-duplicated cumulative anonymous install count
- **Bilingual scope**: both the core layer and all 9 module layers now run through the language packs (3247 keys each for zh_CN / en, aligned key by key); English mode has zero Chinese;
  unextracted strings repo-wide are 0 (enforced key by key by scripts/i18n_audit.py), conventions in [docs/i18n.md](docs/i18n.md)
- Raw output from third-party tools (docker/certbot/apt) and brand proper nouns are not translated
- Commercial advertising systems, affiliate promotions and the private KPanel/.kpb protocol are not part of the capability scope

Full reconciliation and to-dos: [docs/implementation-status.md](docs/implementation-status.md); **for the concrete plan and acceptance criteria of unfinished items**: [docs/roadmap.md](docs/roadmap.md)

---

## Appendix

<details>
<summary><strong>System requirements</strong></summary>

- **Operating systems**: Debian / Ubuntu / CentOS / RHEL / Fedora / Alpine
- **Architectures**: amd64 (x86_64) / arm64 (aarch64)
- **Privileges**: needs to run as root
- **Dependencies**: bash, curl (the installer fills in missing dependencies automatically; the managed application market and Compose backup/migration need Docker + `docker compose` v2)

</details>

<details>
<summary><strong>Usage and exit codes</strong></summary>

```bash
# Main menu (run without arguments)
fusionbox

# Module commands
fusionbox proxy       # Proxy management
fusionbox system      # System management
fusionbox network     # Network tools
fusionbox web         # Web deployment
fusionbox panels      # Panels and tools
fusionbox market      # Application market
fusionbox warp        # WARP management
fusionbox workspace   # Background workspace
fusionbox cluster     # Cluster control

# System commands
fusionbox status      # System status overview
fusionbox version     # Show the version
fusionbox update      # Update FusionBox
fusionbox privacy status|on|off|reset-id  # Anonymous statistics (off by default)
fusionbox lang zh_CN|en|auto             # UI language (switchable at any time, readable without root)
fusionbox uninstall   # Uninstall FusionBox itself (leaves the services installed by the modules alone)
```

Exit code convention for unknown commands:

```bash
fusionbox network bogus
# [ERROR] Unknown subcommand: bogus
# [INFO]  Usage: fusionbox network help      show every command of this module
# [INFO]        fusionbox help network       show this module's detailed help
# [INFO]        fusionbox network            enter the interactive menu
# Exit code 2 (0 on success, 1 for an unknown module)
```

Design intent: a mistyped command gets you an actionable next step and **does not enter the interactive menu** - the menu would block in scripts/CI.

</details>

<details>
<summary><strong>Configuration file</strong></summary>

`~/.config/fusionbox/config.yaml` only declares keys **that are actually read**, so you never "flip a switch that does nothing":

| Key | Effect |
|---|---|
| `general.lang` | Output language `auto` / `zh_CN` / `en` |
| `general.stats` | Anonymous statistics (off by default, same as `fusionbox privacy`) |
| `general.color` | `false` turns off all ANSI colors (handy for log redirection) |
| `system.monitor_interval` | Refresh interval of `fusionbox system monitor` (seconds) |
| `system.backup_dir` | Default directory for `fusionbox system backup\|restore` |
| `network.speedtest_server` | Speed test node: `auto` or a numeric node ID |

Settings such as automatic updates that are not in this file: their real owner is named in the note at the end of the file.

</details>

<details>
<summary><strong>Project structure</strong></summary>

```
FusionBox/
├── fusion.sh                  # main entry script
├── install.sh                 # one-click installer
├── version.txt                # version number
├── README.md                  # project documentation
├── configs/
│   └── config.yaml            # default configuration file
├── src/
│   ├── init.sh                # initialization script
│   ├── lib/
│   │   └── common.sh          # shared function library
│   ├── i18n/
│   │   ├── en.sh              # English language pack
│   │   └── zh_CN.sh           # Chinese language pack
│   └── modules/
│       ├── proxy.sh           # proxy management module
│       ├── system.sh          # system management module
│       ├── network.sh         # network tools module
│       ├── web.sh             # web deployment module
│       ├── panels.sh          # panels and tools module
│       ├── market.sh          # application market module
│       ├── warp.sh            # WARP management module
│       ├── workspace.sh       # background workspace module
│       └── cluster.sh         # cluster control module
├── templates/
│   ├── nginx/
│   └── docker/
├── .cnb.yml                   # CNB pipeline: syntax/static checks + tag release packaging
└── .github/workflows/         # GitHub Actions: release and statistics (install.sh default source)

> Regression checks and behavioral tests (`tests/`, incl. 9 real-machine acceptance scripts) **are not published with the repo**:
> they live only locally and on the verification server, and full regression runs locally and on real hardware;
> the release packaging is unchanged (`export-ignore` keeps them out of the tar.gz).
```

</details>

<details>
<summary><strong>Documentation index</strong></summary>

> Unless marked English, the documents below are currently Chinese-only.

- [Implementation scope and item-by-item reconciliation (the G table)](docs/implementation-status.md)
- [Unfinished items and executable plans](docs/roadmap.md)
- [Anonymous statistics and privacy note](docs/privacy.md)
- [Declarative application catalog and high-privilege boundary](docs/market-catalog.md) (English)
- [UI language and localization conventions](docs/i18n.md)
- [Full change history](docs/CHANGELOG.md)
- [Project home page (Pages)](https://motao123.github.io/FusionBox/)

</details>

---

## Acknowledgements

Thanks to **棉花云** for supporting this project: a quality network provider, [www.88sup.com](https://www.88sup.com).

## License

MIT License (see the [LICENSE](LICENSE) file in the repository root)
