# Changelog

All notable changes to the FirewallFalcon project will be documented in this file.
The format is based on Keep a Changelog and adheres to the `4.6.0_COMMIT_SHA` versioning standard.

## [4.6.0_activation_licensing] - 2026-08-18
### Security
- **Replaced per-client encrypted files with a single activation-gated payload.**
  The tool now ships as ONE encrypted bundle (`menu.enc`) on the repo. The
  decryption key never touches a client — it lives only on a Cloudflare Worker
  (`tools/worker/activation-worker.js`) which releases it exclusively to the
  first server IP that activates a given license id, via KV-backed state.
  A second server on the same id is refused; a revoked id is refused
  everywhere immediately.
- Clients now need a single code (their license id) — no key to copy.
  `install.sh`'s `fm_gate`, and `src/menu.sh` / `src/update_panel.sh`'s
  `_fm_pull_src`, all resolve their own public IP and call the Worker's
  `/activate` endpoint before decrypting `menu.enc`.
- Seller tooling: `tools/issue-client.sh` (issue), `tools/revoke-client.sh`
  (revoke everywhere), `tools/unbind-client.sh` (move a client to a new
  server), `tools/list-clients.sh` (audit), `tools/build-payload.sh`
  (re-encrypt `menu.enc` after editing `src/`). Full setup in `tools/SELLING.md`.
- The previous per-client `clients/<id>.enc` model and its files are removed.

## [4.6.0_licensed_encryption] - 2026-08-18
### Security
- **Per-client encryption gate.** The tool is no longer published in plaintext.
  The protected source (`menu.sh`, `ssh`, `update_panel.sh`, `panel/*`) lives
  only under a git-ignored `src/` and ships as per-client AES-256 bundles at
  `clients/<id>.enc`. The public `install.sh` verifies a license (ID + key),
  decrypts the client's bundle to `/etc/firewallfalcon/.src`, and installs from
  it. menu.sh self-update and panel install/update decrypt the same way using
  the license saved at install time.
- Seller tooling under `tools/` (`issue-client.sh`, `revoke-client.sh`,
  `rebuild-all.sh`) issues, revokes and re-encrypts licenses. See `tools/SELLING.md`.
- Git history was rewritten to remove all previously-published plaintext of the
  protected files.

## [4.6.0_aurora_glass_redesign] - 2026-08-17
### Changed
- **Rebuilt the entire interface as a deep-glass design system, cyan → violet** (`panel/index.html`, `panel/reseller.html`, `menu.sh`):
  - **Web panel:** replaced the whole token layer and every component rule — glass cards now layer a 158° translucent gradient over `blur(28px) saturate(170%)` with an inset top highlight and depth shadow; buttons carry a cyan→violet gradient that shifts on hover; the brand wordmark, active nav rail, tab pills and progress fills all read from one gradient token. Added a drifting aurora field (two blurred colour sources plus a masked grid) behind the glass so the panels have something real to refract.
  - **Reseller portal:** same token set and component treatment, so both surfaces are visually one product.
  - **Terminal menu:** new 256-colour palette (rose / aqua-green / soft amber / steel-indigo frames / ice-cyan brand accent), heavy double-line frames swapped for rounded single-line ones, section headers changed from a centred rule to a left accent bar (`▌ TITLE ─────`), and the progress bar and prompt line redrawn. The SSH login banner (MOTD) palette was moved onto the same colours.
  - The banner's 58-column frame was re-measured after every change; the box-drawing swap is a 1:1 glyph substitution within the same Unicode block, so column widths are unchanged.
  - **Nothing functional was touched.** All 227 element IDs the panel's JavaScript reads are intact, the inline `display` and `width` styles the JS toggles at runtime were left alone, `</head>` (panel.py's session-injection anchor) is preserved, and every `/etc/firewallfalcon/*` path, service and binary name in `menu.sh` is byte-identical to the previous commit.

## [4.6.0_limiter_marker_fix] - 2026-08-17
### Fixed
- **Limiter service was rebuilt and restarted on every menu launch** (`menu.sh`):
  - `setup_limiter_service` wrote the guard line `# ... limiter version 2026-07-23.4` into `/usr/local/bin/firewallfalcon-limiter.sh`, while `sync_runtime_components_if_needed` tested for `...2026-07-23.8`. Because the test is `grep -Fqx` (literal, whole-line), the two could never match.
  - `sync_runtime_components_if_needed` runs on every menu start, so the guard always failed and `setup_limiter_service` re-ran each time: rewriting the limiter script and its unit file, `pkill`-ing the running limiter and restarting the service. That left a short monitoring gap in the multi-login and bandwidth watcher on every launch and slowed menu startup, defeating the very check the guard was written to perform.
  - Bumped the written marker to `2026-07-23.8` so it matches the expected one. Raising the writer rather than lowering the reader means any host still carrying an older limiter script regenerates exactly once with the current body, then settles — a marker that no installation has on disk yet cannot mask stale content.

## [4.6.0_dahoom_rebrand] - 2026-08-17
### Changed
- **Rebranded the displayed product name to `DAHOOM`** (`menu.sh`, `install.sh`, `update_panel.sh`, `ssh`, `README.md`, `panel/*`, `scripts/*`):
  - Unified the three previous display forms — `FM Abu Sultan`, `FirewallFalcon Manager` and `FMA Abu Sultan Edition` — into the single name `DAHOOM` across menu titles, installer and uninstaller messages, the MOTD login banner, systemd `Description=` fields, the web panel title and interface, the default `PANEL_NAME`, the `User-Agent` header, and the VLESS link label.
  - Recomputed the main banner's title width constant from `30` to `13` in both `show_banner` and the cached banner renderer, matching the shorter `🦅 DAHOOM` title so the 58-column frame stays aligned. Changing the text without this constant would have pushed the right border 17 columns out of the frame.
  - **Strictly display-only.** No filesystem path, service name, binary name, system group or function name was touched: `/etc/firewallfalcon/*` (which holds `users.db`), `/usr/local/bin/firewallfalcon`, the four `firewallfalcon-*` systemd units, the `fm` and `menu` commands, the third-party `falconproxy` binary and the `falcon-motd` MOTD files all keep their original names. Verified by asserting the occurrence counts of every internal identifier are unchanged.
  - The original developer's attribution line in `install.sh` is deliberately preserved.

## [4.6.0_github_source_migration] - 2026-08-17
### Changed
- **Migrated the authoritative source from Codeberg to GitHub (`mooa322/fm`)** (`install.sh`, `menu.sh`, `update_panel.sh`, `README.md`):
  - Rewrote every raw-content source from `codeberg.org/aljailane/fm/raw/branch/<BRANCH>/` to `raw.githubusercontent.com/mooa322/fm/<BRANCH>/`, covering the installer, the menu binary, the `ssh` config, the web panel files and the `udp/` binaries.
  - Switched the update-detection endpoint from the Gitea API (`codeberg.org/api/v1/repos/.../branches/`) to the GitHub API (`api.github.com/repos/mooa322/fm/branches/`).
  - Adapted the JSON field read by `jq` from `.commit.id` (Gitea) to `.commit.sha` (GitHub) in all four call sites — `fetch_remote_sha`, `trigger_standalone_update_page`, `_check_remote_ver_bg` and `check_auto_update` — without which update detection would silently resolve to `null` on every check.
  - Repointed the X-UI Panel installation source and documentation link to `mooa322/X-UI`.
  - Moved the bug tracker link to `github.com/mooa322/fm/issues`.
  - No installation, service, protocol or panel logic was altered; the change is confined to source endpoints and the API field name.

## [4.6.0_dev_xui_configs_http_wiki] - 2026-08-17
### Added & Enhanced
- **X-UI Dual HTTP/HTTPS Display & Client Configurations Viewer** (`menu.sh`):
  - Added direct display of both HTTPS and HTTP fallback URLs inside the X-UI Panel info box.
  - Added new option `[5] View Client Inbound Configurations` allowing instant inspection and generation of client connection links (VLESS, VMess, Trojan, Shadowsocks).
  - Added new option `[6] Speed & Performance Tuning Wiki` offering guidance on BBR congestion control, protocols, client applications, and buffer tuning.

## [4.6.0_dev_xui_codeberg_source] - 2026-08-17
### Security & Enhanced
- **Custom Codeberg X-UI Repository Integration** (`menu.sh`):
  - Updated all X-UI Panel automated and interactive installation sources to point to `https://codeberg.org/aljailane/X-UI`.
  - Replaced documentation and repository references with the secured Arabic-enabled Codeberg edition.

## [4.6.0_dev_fast_menu_refresh] - 2026-08-17
### Fixed & Enhanced
- **Menu Loading Latency & Freeze Elimination** (`menu.sh`):
  - Streamlined `refresh_ssh_session_cache` by utilizing a single fast `ps` session scan instead of slow iterative `/proc` directory traversals.
  - Eliminated the 3-second delay/freeze when opening submenus such as `[22] PROTOCOL & PANEL MANAGEMENT`.
  - Re-ordered screen clearing to occur immediately at the start of `show_banner()`.

## [4.6.0_dev_banner_alignment_fm] - 2026-08-17
### Fixed & Enhanced
- **Banner Right Border Alignment Calibration** (`menu.sh`):
  - Calibrated MOTD and in-menu banner row widths from 18 to 17 characters for the left column, ensuring all rows align at 58 visual columns without border protrusion (`║`).
- **Global `fm` CLI Shortcut**:
  - Automatically configured `/usr/local/bin/fm` and `/usr/bin/fm` symlinks pointing to `firewallfalcon`, allowing users to launch the manager using `fm` identically to `menu`.

## [4.6.0_dev_clean_motd_scrollback] - 2026-08-17
### Fixed & Enhanced
- **Login MOTD Simplification & Screen Clearing** (`menu.sh`):
  - Completely suppressed Ubuntu ESM, package updates, and generic system messages upon SSH login.
  - Replaced crowded text with the elegant unified FMA boxed banner.
  - Enhanced `show_banner` with full terminal buffer reset (`\033[H\033[2J\033[3J`) to eliminate residual scrolling and overlapping text.

## [4.6.0_dev_xui_domain_sync] - 2026-08-17
### Added & Enhanced
- **X-UI Automatic Domain Change Detection & SSL Rebuild** (`menu.sh`):
  - Automatically compares active system domain with X-UI database SSL certificate domain.
  - Displays a high-visibility alert when domain mismatch is detected.
  - Adds interactive option `[6] Sync & Rebuild SSL Certificate with New Domain` to automatically obtain Let's Encrypt certificates for the new domain, update SQLite database, and restart the daemon.

## [4.6.0_dev_multi_desec_domain] - 2026-08-17
### Added & Enhanced
- **Multi-Domain Free Root DNS Selector (aljailane.dedyn.io & aljvpn.top)** (`menu.sh`):
  - Added interactive dialog `select_free_domain_dialog` to choose between `aljailane.dedyn.io` (Default) and `aljvpn.top` (New).
  - Integrated dedicated deSEC tokens for both root domains with live CRUD API support.
  - Dynamically stores `ROOT_DOMAIN` and `DESEC_TOKEN` inside `/etc/firewallfalcon/dns_info.conf` for seamless deletion and IP synchronizations.

## [4.6.0_dev_purge_3xui] - 2026-08-16
### Removed & Enhanced
- **3X-UI Panel Deprecation & Complete Purge** (`menu.sh`):
  - Completely purged option `[8] 3X-UI Panel` and all associated 3X-UI installer functions from `menu.sh`.
  - Streamlined management panel options to a dedicated single `[8] X-UI Panel`.
  - Fixed `show_xui_access_info` to guarantee live extraction and presentation of `webBasePath`, SSL Domain, and Direct URL.

## [4.6.0_dev_banner_fma] - 2026-08-16
### Fixed & Enhanced
- **Banner Branding & Border Alignment Fix** (`menu.sh`):
  - Updated main title branding to `🦅 FMA  Abu Sultan Edition` (FirewallFalcon Manager Abu Sultan).
  - Fixed right-hand border protrusion (`║`) by calibrating character and dynamic padding lengths for title and badge rows.

## [4.6.0_dev_xui_ssl_basepath] - 2026-08-16
### Fixed & Enhanced
- **X-UI / 3X-UI Certificate Mirroring & Web Base Path Auto-Discovery** (`menu.sh`):
  - Rewrote SQLite reader in `show_xui_access_info` to evaluate output directly via python without `jq` dependency.
  - Automatically auto-discovers Let's Encrypt / ACME certs and mirrors them to `/root/cert/{domain}/` and `/root/cert.crt`.
  - Automatically queries and includes the active `webBasePath` in direct HTTPS URLs, preventing 404 Not Found errors when accessing X-UI with a custom or randomized URL path prefix.

## [4.6.0_dev_banner_compact] - 2026-08-16
### Fixed & Enhanced
- **Banner Layout & User Card Compact Framing** (`menu.sh`):
  - Tightened badge spacing between status counters (`🟢 Active │ 🟡 Locked │ 🔴 Expired │ 👥 Total`).
  - Added full double-line borders (`║ ... ║`) matching 58-column layout with dynamic padding calculation.
  - Eliminated excess padding inside count badges to keep the entire status card section cleanly framed.

## [4.6.0_dev_2305c87] - 2026-08-16
### Fixed & Enhanced
- **Autologin Token Engine - Deep Fix** (`panel/panel.py`, `panel/index.html`):
  - `consume_autologin_token()` now force-reloads from disk on every call, picking up tokens
    written by `menu.sh`/`generate_autologin_link_sh` without requiring panel restart.
  - HTML `</head>` injection now uses case-insensitive regex (`(?i)</head>`) preventing
    injection failure on edge-case HTML templates.
  - Added fallback redirect with cookies if HTML file is missing during autologin.
  - `index.html`: Replaced inline `api()` call for autologin with dedicated `tryAutologin()`
    using raw `fetch()` to bypass `api()`'s 401-exception guard, which previously killed the
    autologin flow before the session token could be saved to `localStorage`.
  - Fixed `credentials:'same-origin'` to `credentials:'include'` in `api()` for proper
    cross-context cookie propagation on plain HTTP.
  - Added `/api/autologin` to the 401-bypass allowlist in `api()`.
- **Resilient Credential Parser** (`panel/panel.py`):
  - `get_panel_creds()` now uses `get_panel_conf_path()` to auto-discover `panel.conf` across
    three known paths (`/etc/firewallfalcon/panel.conf`, `/etc/firewallfalcon/panel/panel.conf`).
  - Default `PANEL_USER` is now `"admin"` instead of empty string preventing login failure
    when `panel.conf` is missing or malformed.
  - Keys are now normalized with `.upper()` before matching, handling any case variation.
- **Premium Banner Redesign** (`menu.sh`):
  - Replaced flat banner with an elegant box-art header using Unicode box-drawing characters
    (`╔═╗`, `║`, `╚═╝`, `┌┤├┘`).
  - System stats (OS, Memory, Sessions, Load) now displayed in a structured bordered table.
  - User status bar (Active/Locked/Expired/Total) rendered in an aligned bottom row.
- **`new_panel` Branch Isolation** (`menu.sh`, `update_panel.sh`):
  - `PANEL_REPO_BASE` now points to `branch/new_panel/panel` — panel files are sourced
    exclusively from the dedicated `new_panel` branch, fully independent of `dev`/`main`.
  - Removed all `v2ray_manager.py` download references from `update_panel.sh`.
  - `install_web_panel()` and `update_web_panel()` now copy `panel.py` to both
    `/usr/local/bin/firewallfalcon-panel.py` AND `/etc/firewallfalcon/panel/panel.py`
    and symlink to `/usr/local/bin/panel.py`.
  - `PANEL_PORT` is now persisted into `panel.conf` during installation.
  - `update_web_panel()` shows a fresh 1-Click Auto-Login link after successful update.

## [4.6.0_dev_autologin] - 2026-08-16
### Added & Enhanced
- **Resilient Web Panel Authentication & 1-Hour Dynamic Auto-Login Engine**:
  - Solved login credential verification issues by adding case-insensitive username normalization and multi-factor validation supporting both SHA-256 password hash and plaintext comparison.
  - Implemented dynamic 1-Hour Ephemeral Auto-Login engine (`generate_admin_autologin_link`) generating single-use direct login tokens with automatic expiration after 3600 seconds.
  - Integrated 1-Click Auto-Login URL generation directly into CLI credentials display (`show_panel_credentials` & `install_web_panel`) and API endpoint (`/api/autologin-link`).
  - Added dual-mode token authentication fallback (`Authorization: Bearer <token>` & `X-Session-Token: <token>`) ensuring reliable web panel access even when browsers restrict third-party cookies or SameSite policies over plain HTTP.
- **Web Control Panel Focus & V2Ray Protocol Decoupling**:
  - Cleaned and streamlined the Web Control Panel (`panel/index.html` & `panel/panel.py`) by removing the V2Ray tab, client controllers, node cluster modals, and user management endpoints.
  - Xray and V2Ray protocols are now exclusively managed via their dedicated specialized panels (**3X-UI** & **X-UI**).
  - Preserved the real-time **Xray Core** service status monitor and health checks inside the Dashboard overview and Services tab.
- **Automated Free deSEC SSL Domain & HTTPS Panel Integration**:
  - Implemented 1-click automated 4-step quick installation wizard for both **3X-UI** (MHSanaei) and **X-UI** (alireza0).
  - Automatically provisions dedicated free dynamic subdomains under `*.aljailane.dedyn.io` with instant dual-stack `A` (IPv4) and `AAAA` (IPv6) DNS records via deSEC API.
  - Automatically requests and applies official Let's Encrypt SSL/TLS certificates via Certbot in standalone mode without manual domain input.
  - Configures dedicated ports (`2053` for 3X-UI, `54321` for X-UI) and opens them automatically across all firewall layers (UFW, IPTables, Firewalld).
  - Built comprehensive real-time Access Info card displaying live service status, Direct Domain HTTPS URL, Direct IP HTTPS URL, credentials, and web base path.
- **Intelligent SSL Auto-Discovery & CLI Synchronization**:
  - Enhanced `show_xui_access_info` and `repair_xui_access` to auto-discover existing certificates in `/etc/letsencrypt/live/` and automatically link them into `/etc/x-ui/x-ui.db`.
  - Automatically mirrors SSL certificates to standard paths (`/root/cert.crt` and `/root/private.key`) ensuring full compatibility with the interactive `x-ui` CLI manager.
- **Dynamic Subdomain Architecture (`alj-xxxxxx`)**:
  - Standardized the automated subdomain prefix to `alj-$(tr -dc a-z0-9 < /dev/urandom | head -c 6)` (e.g. `alj-7ym3aq.aljailane.dedyn.io`), fully adhering to RFC 1035 / RFC 1123 DNS standards and CA/Browser Forum SSL requirements.
- **Zero-Latency (0ms) CLI Menu Performance**:
  - Replaced heavy `systemctl list-unit-files` calls and multi-megabyte binary inspection (`strings /usr/local/x-ui/x-ui`) with ultra-fast in-memory `pgrep` checks and lightweight filesystem stat lookups.
  - Slashed menu loading and navigation transition times from ~1.5s down to <10ms for instantaneous responsiveness.
- **Interactive Animated Progress Bars**:
  - Replaced silent freeze and hanging inputs during installation and uninstallation with smooth, non-blocking visual progress bars with live percentages (`0%` to `100%`).
- **Clean System Login MOTD & ESM Clutter Purge**:
  - Completely purged intrusive Ubuntu ESM / ESM Apps, Landscape, and update-notifier notices from SSH login prompts (`/etc/update-motd.d/`).
  - Deployed an elegant, clean, unified FirewallFalcon login MOTD banner across Ubuntu, Debian, AlmaLinux, and Rocky Linux systems.

### Fixed & Resolved
- **SQLite Database Settings Duplicate Keys Bug**:
  - Diagnosed and resolved the root cause of panel port binding failures where 3X-UI/X-UI continued listening on random ports due to duplicate rows in the `settings` table without a unique index on `key`.
  - Replaced `INSERT OR REPLACE` with parameterized `DELETE FROM settings WHERE key IN (...)` followed by clean parameterized insertions.
- **X-UI Installer 404 Download & Invalid Port Flag**:
  - Removed accidental `-y` flag passing in `alireza0/x-ui` installer to prevent broken GitHub release asset download URLs (`download/-y/...`).
  - Added automated port feeding (`y\n54321\n`) to eliminate `invalid value "n" for flag -port: parse error` during automated installations.
- **Sequential CLI Menu Renumbering (1–37)**: Completely reorganized the terminal menu into clean, continuous, intuitive sequences:
  - `[1]-[14]`: SSH & Core User Management
  - `[15]-[21]`: V2Ray & Xray Protocols (`[15] Core`, `[16] Create`, `[17] List`, `[18] Links/QR`, `[19] Renew`, `[20] Delete`, `[21] Import SSH`)
  - `[22]-[25]`: VPN & Protocols
  - `[26]-[37]`: System Settings & Automation
  - `[98]`: Update Tool | `[99]`: Uninstall | `[0]`: Exit
- **Robust Xray Core Management & Diagnostics**:
  - Added safe installation, auto-repair reinstallation (`reinstall_vless_reality`), clean removal, service startup validation, and real-time journalctl diagnostics.
  - Added real-time config testing (`xray -test -config`) before startup to eliminate `(Stopped)` status issues.
- **Single-Notice Unified Update Indicator**:
  - Removed duplicate, distracting update prompts across submenus and startup dialogs.
  - Retained a single, clean status indicator next to `[98] Update Tool (🚀 Update Available)` on the main screen.
  - Dynamic universal subscription builder generating localized node links (`Reality`, `VMess CDN`, `VLESS WS`, `Trojan gRPC`) per authorized server.
  - Dedicated Web UI modal `#mv2nd` for managing connected nodes and clusters.
- **Decoupled V2Ray / Xray Services & Storage Engine**:
  - Implemented isolated V2Ray user database (`/etc/firewallfalcon/v2ray_users.db`) with distinct UUIDs, expiration dates, quotas, and multi-tenancy.
  - Implemented dynamic Xray JSON config generator (`v2ray_manager.py`) supporting VLESS Reality, VMess WebSocket (CDN), VLESS WS, and Trojan gRPC inbounds.
  - Built universal public subscription endpoint (`/sub/v2ray/<token>`) auto-adapting feeds for v2rayNG, Streisand, Shadowrocket, Clash, and Sing-box.
- **V2Ray Web Control Panel (`#tab-v2ray`)**:
  - Added dedicated navigation and section for V2Ray users, inbounds configuration, reality keypair generator, and live Xray service controllers.
  - Added one-click link exporter (`vless://`, `vmess://`, `trojan://`) with integrated dynamic mobile QR Code viewer.
- **Enhanced CLI Menu (`menu.sh`)**: Overhauled Xray protocols menu option `[16]` with full interactive lifecycle management (install, renew, link export, and reality keys).
- **Extended DNS Record Types & Adaptive Form Fields**:
  - Expanded Cloudflare DNS record support across all major types: `A`, `AAAA`, `CNAME`, `TXT`, `MX`, `NS`, `PTR`, `CAA`, `SRV`.
  - Added dynamic field adaptation showing tailored inputs based on selected record type (e.g. Mail Priority for `MX`, CA Tags & Values for `CAA`, Service/Protocol/Port/Weight for `SRV`).
- **Interactive Help Guide Tooltips (`❓`) & Comprehensive DNS Guide Modal**:
  - Integrated interactive question-mark buttons (`❓`) beside every single field and setting with instant explanations.
  - Added dedicated tabbed Cloudflare Help Guide modal covering record types, `@` apex roots, Proxy CDN vs Direct DNS Only, and TTL propagation.
- **Relative Time Ago Badges & Condensed Table UI**:
  - Added live relative timestamps (e.g. 2 mins ago, 1 hour ago, 3 days ago) for last record updates across desktop tables and mobile cards.
  - Streamlined and condensed all table headers, action buttons, and status badges.
- **Cloudflare DNS Form Experience**: Made DNS record name field fully optional (defaults to `@` for apex domain if left blank) and removed strict restrictions to match native Cloudflare dashboard flexibility.
- **Cloudflare DNS Error Reporting & Input Sanitization**:
  - Fixed internal `HTTPError` handling in `cf_api_request` to parse and extract full Cloudflare API error chains rather than swallowing details and returning generic `HTTP 400: Bad Request`.
  - Added automatic payload sanitization (cleaning protocol prefixes `http://`, trailing slashes, and attached ports from IP values).
  - Enforced Cloudflare proxy rules: automatically locking `ttl=1` (Auto) whenever proxy is enabled and disabling proxy for non-proxiable record types (`TXT`, `MX`, etc.).
- **Isolated Multi-Portal Session Architecture**:
  - Completely separated authentication session cookies between the Admin Control Panel (`session` / `admin_session`) and the Reseller Web Portal (`reseller_session`).
  - Logging in or logging out of the Reseller portal now operates strictly on `reseller_session`, leaving the Admin session fully active and secure without cross-portal session termination.
- **Cloudflare DNS Audit Logging Bug**: Resolved `TypeError: check_session() got an unexpected keyword argument 'handler'` error by updating `check_session(headers, handler=None)` to accept the optional handler argument across audit logging routines.
- **Reseller Profile Quota & Expiry Calculation Fix**:
  - Resolved root cause of `-- / --` quota indicator and `--` expiration date display by adding case-insensitive username matching, trimmed whitespace sanitization, and immediate profile rendering upon page initialization.
  - Added fallback profile data in admin branch so admin users previewing the reseller portal experience complete data rather than unpopulated values.
  - Converted entire changelog documentation to strict English (`en`) standard.
- **Cumulative Bandwidth Stacking & Renewal Hierarchy**:
  - **➕ Cumulative Bandwidth Addition**: Added option to stack added bandwidth (`+GB`) on top of current bandwidth quota, carrying over unused gigabytes seamlessly.
  - **3 Clear Bandwidth Modes**: Quick selectors for `➕ Add Cumulative (+GB)`, `🔄 Reset Usage (0 GB Cycle)`, and `⏳ Keep Current`.
  - **Enhanced Wizard Layout**: Clean 5-step intuitive flow (User summary ➔ Duration & Time stacking ➔ Bandwidth options ➔ Device limit ➔ Live calculated preview).
- **Reseller Portal Distinct Design & Rubik Font**:
  - **Distinct Cyber Cyan Palette**: Replaced admin red with an ultra-sleek, modern Cyber Cyan / Sapphire Blue theme (`#0284c7` & `#38bdf8`) with deep slate card surfaces.
  - **Google Font 'Rubik' Integration**: Applied Google Font `Rubik` globally across all components, buttons, forms, tables, badges, toasts, and inputs.
  - **Sidebar Quick Navigation Links**: Added quick navigation links in the mobile & desktop sidebar for immediate access to sections (`Overview & Balance`, `Users Management`, `New User`, `Trial User`, `Bulk Generation`, `Refresh Data`).
- **Cumulative Renewal & Device Limit Setting**:
  - **🔄 Cumulative Renewal Toggle**: Added option to add renewal duration on top of remaining days or start fresh from current moment with live interactive preview.
  - **📱 In-Wizard Device Connection Limit**: Added direct control to set/adjust device connection limits (`conn_limit`) with quick-select buttons `[1]` `[2]` `[3]` directly inside the renewal wizard.
  - **Condensed Modal UI**: Streamlined and shortened all modal labels and descriptions for clean mobile readability without visual clutter.
- **Reseller Portal Mobile UI & Quota Overhaul**:
  - **Google Font Integration**: Integrated Google Font `Rubik` and `JetBrains Mono` for maximum legibility and crisp visual hierarchy.
  - **Mobile Sidebar Drawer & 4-Button Bottom Bar**: Added sleek sliding drawer navigation and bottom bar (`Home`, `Users`, `Create`, `Menu`) tailored for mobile screens.
  - **Accurate Real-Time Quota & Expiry Calculation**: Fixed quota indicator showing `created / max` with interactive visual progress bar and real-time remaining days badge.
  - **Interactive Renewal Wizard**: Full support for both duration extension and package reset with instant previews.
- **Interactive Subscription Renewal Wizard**:
  - **Renewal Modes**: Added two intuitive renewal options:
    1. **⏳ Extend Duration Only**: Extends expiration date without resetting current bandwidth usage.
    2. **🚀 Full Package Reset & Renew**: Extends expiration date and resets the bandwidth usage counter back to 0 GB for a fresh cycle.
  - **Live Visual Preview**: Instant real-time preview of the new expiration date, bandwidth status, and credit deduction before confirmation.
  - **Clipboard Copy Overhaul**: Added robust cross-browser clipboard copying with non-secure/HTTP fallback to resolve copy button issues on mobile and desktop.
- **Dedicated Isolated Reseller Web Portal (`/reseller_<secret>`)**:
  - **Security Isolation**: Created dedicated, standalone Reseller Portal (`panel/reseller.html`) accessible strictly via unique secret URL path (e.g. `:44380/reseller_ou40q64b`).
  - **Zero Exposure**: Resellers have no access to server management, Cloudflare, protocols, firewall, or internal system configurations.
  - **Full Reseller Toolkit**: Live Quota/Credits indicator, User creation with granular permission limits (max connections, bandwidth, trial/bulk gates), Quick credential copy, renew, and mobile-responsive cards.
  - **Secret Path Management**: Admin can view, copy, and rotate the Reseller Secret Path anytime directly from the Resellers Tab or API.
- **Interactive Performance Charts & Comprehensive Reports Dashboard**:
  - **Dashboard Real-Time Charts**: Added SVG live sparkline/area charts for CPU load, RAM allocation, concurrent live sessions, and 7-day weekly bandwidth traffic comparison.
  - **Dedicated Reports & Analytics Tab**: Added Reports & Analytics tab with KPI summaries, 7-day traffic timeline, account status distribution, 24-hour peak load curve, top bandwidth consumers table, and JSON report export.
  - **Zero External Dependencies**: Built using ultra-fast vanilla SVG charting engine with smooth, silent in-place updates.
- **Cloudflare Integration Security & Panel Architecture Overhaul**:
  - **Security isolation**: Removed token configuration modals from the Web Panel; Cloudflare API credentials are strictly configured via the secure Terminal tool (`menu.sh` -> `/etc/firewallfalcon/cloudflare.info`).
  - **Smart 5-Second Cache & Auto-Sync**: Added a 5-second in-memory server cache in `panel.py` to prevent Cloudflare API rate limits, with immediate cache invalidation on any record mutations.
  - **Live Auto-Polling**: The Web Panel automatically polls DNS records and status every 5 seconds when the Cloudflare tab is open without page flicker.
  - **One-Click Actions**: Integrated instant Server IP Sync button, quick DNS record creation/editing/deletion, and one-click Cloudflare Proxy toggling (🟠/⚪).
  - Fixed backend helper functions in `panel.py` (`read_cloudflare_config`, `cf_api_request`, `write_cloudflare_config`).
- **Cloudflare DNS Integration - Zone Auto-Discovery (CLI & Web Panel)**:
  - Simplified credentials setup: users only need to input their Cloudflare API Token.
  - Automatically queries Cloudflare API v4 and lists all available domains/zones linked to the account.
  - Allows selecting the desired domain as the default active domain, with instant domain switching at any time.
  - Added full cancellation and return support (`0 to cancel`) across all interactive steps.
- **Cloudflare DNS Integration (CLI & Web Control Panel)**:
  1. **Terminal CLI Integration (`menu.sh`)**:
     - Activated option `[2] Cloudflare Integration` under `[15] Domain & DNS`.
     - Added `cloudflare_menu` with interactive API Token & Zone ID credential setup and real-time validation against `api.cloudflare.com/client/v4/zones`.
     - Added One-Click A Record Sync to Server IP (`update_domain_ip` and option 2 in Cloudflare menu).
     - Added live toggle for Cloudflare CDN Proxy mode (🟠 Proxied vs ⚪ DNS Only).
     - Added live DNS record inspector directly within the terminal UI.
     - Updated `detect_preferred_host` to automatically recognize the active Cloudflare root domain for SSL Certbot, Edge stack, and VLESS clients.
  2. **Web Control Panel Integration (`panel/panel.py` & `panel/index.html`)**:
     - Added dedicated Cloudflare DNS management tab (`#tab-cloudflare`) in the navigation bar.
     - Implemented backend REST API endpoints: `GET /api/cloudflare`, `POST /api/cloudflare/config`, `GET /api/cloudflare/records`, `POST /api/cloudflare/records`, `PUT /api/cloudflare/records/<id>`, `DELETE /api/cloudflare/records/<id>`, and `POST /api/cloudflare/sync-ip`.
     - Built comprehensive frontend UI: Active Zone status banner, secure API Token credential configuration modal, live DNS Records table & mobile cards, one-click Server IP sync, and instant Cloudflare Proxy toggle switches per record.
     - Integrated Cloudflare DNS actions into admin audit trails (`admin_audit.log`).

## [4.5.0_beta_476a173] - 2026-08-15
### Fixed & Improved
- **100% Self-Contained Binary Assets (Official Falcon Proxy Integration)**:
  1. Synchronized and deployed the official compiled `falconproxy` binary into `udp/falconproxy`, updating `install_falcon_proxy` in `menu.sh` to download and install the official binary directly from the Codeberg repository (`codeberg.org/aljailane/fm`).
  2. Bundled and mirrored all binary packages (`udp-custom`, `udp-zivpn` AMD64/ARM/ARM64, `dnstt-server` AMD64/ARM64, `falconproxy`) inside the repository's `udp/` directory, updating all download sources in `menu.sh` to use the Codeberg repository (`codeberg.org/aljailane/fm`) directly.
- **DNSTT deSEC Integration & Syntax Error Fix**:
  1. Fixed `jq` parsing crash in deSEC API response handling and added clear error details.
  2. Added an automatic fallback prompt to enter custom NS and Tunnel domains directly if deSEC domain is expired/unavailable.
  3. Switched default deSEC root domain to the active verified domain `aljailane.dedyn.io` with full API verification and automated CRUD DNS operations.
  4. Added support for external deSEC configuration file (`/etc/firewallfalcon/desec.conf`).

## [4.5_beta_bf655ef] - 2026-08-11
### Fixed
- **Logging System Implementation**:
  1. **TUI Logins & Logouts**: Added real-time LOGIN/LOGOUT connection tracking (including remote IP lookup via `ss -tp`) to the background anti-multi-login daemon `firewallfalcon-limiter`, logging to `/etc/firewallfalcon/logs/client_connections.log`.
  2. **Service Outage Guard Installation**: Inlined and integrated the `firewallfalcon-health` Python daemon installation and service registration in `menu.sh` during `initial_setup`, fixing empty `service_health.log` issue.
  3. **Web Panel Audit Trails**: Integrated `_log_action` API calls inside `panel/panel.py` for user creation, modification, deletion, renewal, locking, speed limiting, and firewall changes, saving logs to `/etc/firewallfalcon/logs/admin_audit.log`.
- **Panel Direct Install Prevention**: Added a check in `update_panel.sh` to prevent direct panel installation if option 21 in the terminal menu was never run, avoiding port conflicts.
- **Backup Selection Interface**: Refactored `restore_user_data` in `menu.sh` to display a numbered list of available backups with sizes and added a `[0] Return/Cancel` option instead of requiring manual path entry.
- **Discrepancy in Update Version Tag**: Dynamically resolved the `_beta_` tag naming mismatch in `get_current_version_tag` depending on the active update channel.
### Added
- **Dynamic Update Channels (Stable & Beta)**: Added a remote update separation system between `Stable` (main branch) and `Beta` (beta2 branch) with interactive prompts in the installer (`install.sh`), automatic upgrade channel detection, and a `Switch Update Channel` option inside the Update Manager in `menu.sh`.

## [4.5.0] - 2026-08-11
### Stable Production Release
- **Merged `beta2` into `main`**: Official 4.5.0 production release.
- **Protocol Status Detection**: Multi-path Systemd unit verification covering all 13 core services and daemons.
- **Categorized Logging & Health Guard**: 5 categorised log streams with auto-healing system daemon.
- **Clean UI & Secret Path Routing**: Streamlined web panel routing and clean 2-column emoji-free terminal UI menus.
### Added
- **Advanced Categorized Logging & Service Outage Auto-Healing Subsystem**:
  1. **5 Categorized Log Streams (`/etc/firewallfalcon/logs/`)**:
     - `admin_audit.log`: Audit trail for all operator actions (User Create/Edit/Delete/Lock/Unlock/Renew, Speed Limit changes, Reseller updates).
     - `client_connections.log`: Session logins/logouts, duration, remote IPs, and bandwidth quota threshold alerts (80% / 100%).
     - `service_health.log`: Automatic background daemon monitoring 8 core services (BadVPN, UDP Custom, HAProxy, Nginx, SlowDNS, ZiVPN, X-UI, Panel), logging outages and auto-healing restarts.
     - `security_alerts.log`: IPTables Blacklist blocks, failed SSH login attempts (`lastb`), Anti-MultiLogin kicks, Anti-Torrent triggers.
     - `reseller_audit.log`: Sub-account creations, credit transactions, and reseller operations.
  2. **Service Outage Detector Daemon (`scripts/firewallfalcon-health.py`)**: Runs every 30s as a systemd daemon to detect crashes, auto-restart failed services, and log RAM/Disk resource warnings (≥90%).
  3. **Web Control Panel Logs Hub (`#tab-logs` & `/api/logs`)**: Tabbed log viewer supporting category switching, live search, severity badges (`INFO`, `WARN`, `CRIT`), auto-refresh polling, and log exports.
  4. **Terminal UI Logs Hub (`[30] Advanced Logs Hub`)**: Interactive TUI log viewer supporting per-category viewing, real-time log streaming (`tail -f`), log searches, and log purging.

## [4.5_beta_2f222c0] - 2026-08-09
### Added
- **Speed Limits Enhancements**:
  1. **Speeds Tab Dropdown Fix**: `lSP()` now dynamically loads user accounts if `U` array is empty, ensuring all managed users appear in the `Speeds` selection dropdown.
  2. **Speed Limits Column in Accounts Table**: Added a dedicated `Speed` column displaying current limit (e.g. `⚡ 50M` or `∞`) in both table and mobile card views.
  3. **Max Speed Limit Field in Edit Account Modal**: Added `Max Speed Limit (Mbps, 0=Unlimited)` input field to `#meu` modal so administrators can adjust per-user speed limits directly when editing accounts.
- **Web Control Panel (10 New Features)**:
  1. **Live Monitor Tab (`/api/monitor`)**: Real-time SSH session monitoring, online session count, duration, and instant Kick capability (`POST /api/monitor/{u}/kick`).
  2. **IP Firewall Control (`/api/firewall`)**: Manage IPTables Blacklist & Whitelist rules directly from the web panel, add/remove IPs, flush rules.
  3. **Per-User Speed Limiter (`/api/user-speeds`)**: Configure individual bandwidth speed limits (Mbps) per user from the panel interface.
  4. **Connection History Viewer (`/api/users/{u}/history`)**: View last 50 successful SSH logins and last 20 failed attempts per user.
  5. **Quick Stats Cards**: Dashboard widgets for Disk Usage %, Expired Accounts count, Locked Accounts count, and Near-Quota (≥80%) accounts count.
  6. **Multi-User Batch Operations**: Select multiple users with checkboxes to perform bulk Lock, Unlock, Renew, or Delete.
  7. **User Data Exporter (`/api/users/export`)**: Export managed user database to CSV or JSON formats.
  8. **Dark / Light Theme Toggle**: Seamless theme switcher persisted in browser local storage.
  9. **Auto-Refresh Rate Control**: Adjustable dashboard auto-polling rate (Off, 5s, 10s, 30s).
  10. **Panel Access Auditor (`/api/panel-logs`)**: Log and view administrative panel logins with IP address tracking.

## [4.5_beta_90b3f9d] - 2026-08-09
### Added
- **IP Firewall [27]**: Whitelist/Blacklist module using a dedicated `FF_FIREWALL` iptables chain. Supports adding/removing IPs and CIDRs to block (DROP) or always-allow (ACCEPT). Whitelist rules always take priority over blacklist. Rules are stored persistently and can be re-applied after reboot.
- **Per-User Speed Limiter [28]**: Individual bandwidth shaping per SSH user using `tc htb` + `iptables mangle uid-owner`. Each user gets their own tc class identified by their UID. Limits stored in `/etc/firewallfalcon/user_speeds.conf` and can be re-applied after reboot. Supports set/remove/flush all.
- **Connection Logs Export [29]**: Full SSH connection log viewer and exporter. Shows last 30 logins with color coding, failed attempts via `lastb`/`journalctl`, per-user export to `/root/ff_log_*.log`, full export with managed-user summary, and live who-is-online table.

## [4.5_beta_7a64e2b] - 2026-08-09
### Added
- **Live Session Monitor [26]**: Real-time SSH session dashboard showing each online user's Remote IP, Login Time, connection Duration, and Session Count with color coding (green=1, yellow=2, red=3+). Features auto-refresh every N seconds (configurable), `[k]` Kick user to disconnect all their sessions via `kill -HUP`, `[r]` instant refresh, and `[5]` to set custom refresh interval. Duration is computed directly from `/proc/<pid>/stat` for accuracy.

## [4.5_beta_c9e7c81] - 2026-08-09
### Fixed
- **Speed Limiter HTB Quantum Warnings**: Suppressed `sch_htb: quantum of class is big` warnings by adding `r2q 1` to the root qdisc and computing explicit `burst` sizes from the Mbps rate. All `tc` stderr is redirected to `/dev/null` for a clean UI output.

## [4.5_beta_60a4781] - 2026-08-09
### Fixed
- **Main Menu Badge Column Alignment**: Fixed ANSI escape codes being counted as visible characters by `printf %-Ns %b`, causing column 2 to shift. All badge lines now embed the badge text directly in the format string with manually computed trailing spaces so column 2 always starts at the same position.

## [4.5_beta_bcf670c] - 2026-08-09
### Fixed
- **Main Menu Badge Audit**: Fixed `[24] Auto-Healing` missing its own `[New]` badge (was sharing with `[25]`). Added `[Updated]` to `[12] Protocols` (now contains VLESS REALITY). Each new/updated option now has its own correctly placed badge.

## [4.5_beta_c922195] - 2026-08-09
### Fixed
- **Update Detection Always Showing "Up to date"**: Root cause was `get_installed_sha()` returning full version string (e.g. `4.5_beta_abc1234`) instead of the raw 7-char SHA, causing SHA comparison to always fail. Fixed by stripping any prefix inside `get_installed_sha()`, enforcing `${#sha} -eq 7` guards in all comparison sites (`refresh_banner_cache`, `check_auto_update`, `trigger_standalone_update_page`), and always warming the banner cache after live API fetches.

## [4.5_beta_305027f] - 2026-08-09
### Added
- **VLESS REALITY User Management Badge**: Added prominent `${C_CYAN}[VLESS]${C_RESET}` badge to `Client Config` option `[8]` in `main_menu()` and `[VLESS Supported]` tag header in `generate_client_config` for clear protocol visibility.

## [4.5_beta_d27e8c6] - 2026-08-09
### Changed / Refactored
- **VLESS REALITY Architecture Separation**: Standardized `vless_reality_menu` in protocol settings to pure service lifecycle management (`service_action_menu` for Install / Uninstall), while moving user subscription links and QR Code generation into the primary User Management & Client Configuration flows (`generate_client_config` / `[8] Client Config`).

## [4.5_beta_f6368e1] - 2026-08-09
### Changed / Refactored
- **New Feature Badge Standardization**: Standardized green `${C_GREEN}[New]${C_RESET}` badge indicators across all newly introduced features (`Domain & DNS`, `Anti-MultiLogin`, `Telegram Bot`, `Auto-Healing`, `Speed Limiter`, and `VLESS REALITY`).

## [4.5_beta_7320d1f] - 2026-08-09
### Added
- **Auto-Healing Service Guard**: Background health inspector (`run_auto_healing_check`) checking systemd services (`badvpn`, `udp-custom`, `haproxy`, `nginx`, `dnstt`, `falconproxy`, `zivpn`, `x-ui`) every 2 minutes via cron (`_run_auto_healing`) and auto-restarting crashed services with Telegram alerts.
- **VLESS / REALITY Protocol Integration**: Comprehensive Xray core module (`vless_reality_menu`) supporting 1-click VLESS REALITY installation, service control, and subscription link / QR Code generation.
- **Speed Limiter & Traffic Shaping**: Linux `tc` HTB qdisc bandwidth shaper (`speed_limiter_menu`) supporting global interface rate limiting in Mbps.

## [4.5_beta_eb7032c] - 2026-08-09
### Fixed
- **Main Menu Alignment**: Corrected two-column table padding across all rows (`[14]`, `[15]`, `[21]`, `[22]`, `[23]`) so Column 2 options align with 100% pixel-perfect precision.

## [4.5_beta_e33d260] - 2026-08-09
### Added
- **Anti-MultiLogin Guard Engine**: Automated background check (`check_and_kill_multilogin`) running every minute via cron (`_run_multilogin`) to enforce connection limits (`limit`) and terminate excess sessions.
- **Telegram Bot & Cloud Backup Hub**: Full Telegram integration (`telegram_bot_menu`) providing instant Telegram alerts on user creation/deletion/locks, test notification dispatch, and 1-click cloud backup transmission of `.tar.gz` databases to Telegram Admin Chat.

## [4.5_beta_308b7a4] - 2026-08-09
### Added
- **Main Menu Navigation**: Added colored `${C_GREEN}[Updated]${C_RESET}` badge next to option `[15]` `Domain & DNS`.

## [4.5_beta_421d396] - 2026-08-09
### Changed / Refactored
- **Main Menu Navigation**: Renamed option `[15]` label from `Free Domain` to `Domain & DNS` to reflect the multi-featured Domain & DNS Management Hub.

## [4.5_beta_9609c35] - 2026-08-09
### Added
- **Domain & DNS Management Hub**: Comprehensive redesign adding Custom Domain Setup (`/etc/firewallfalcon/custom_domain.info`), Dynamic IP Auto-Update (`update_domain_ip`), DNS Resolution & Propagation Inspector (`inspect_dns_resolution`), Let's Encrypt SSL Certificate Manager (`ssl_cert_manager_menu` via Certbot), and a Cloudflare Integration placeholder (`[2] Cloudflare Integration (SOON)`).

## [4.5_beta_97f63bd] - 2026-08-09
### Changed / Refactored
- **Auto-Reboot Management**: Shortened title to `AUTO REBOOT`, streamlined schedule display, and updated option choices (`[1] Daily Reboot (00:00)`, `[2] Disable Reboot`, `[0] Return`).
- **Cleanup Expired Users**: Simplified expired user detection layout and confirmation handling (`CLEANUP EXPIRED USERS`).
- **Backup User Data**: Converted backup management into an interactive zero-path-entry menu (`[1] Create Backup Now`, `[2] Purge Old Backups (Keep Last 5)`).

## [4.5_beta_294abe2] - 2026-08-09
### Changed / Refactored
- **Torrent Blocking Management**: Shortened header title to `TORRENT BLOCKING`, refined status indicator (`Active (Blocked)` / `Inactive (Allowed)`), and updated choice labels to `[1] Enable Blocking`, `[2] Disable Blocking`.

## [4.5_beta_9a22757] - 2026-08-09
### Changed / Refactored
- **Free Domain & SSH Banner Sub-menus**: Unified and shortened option labels for `FREE DOMAIN (deSEC)` and `SSH LOGIN BANNER`.

## [4.5_beta_971f8e4] - 2026-08-09
### Added
- **Interactive Update Notification Screen**: Redesigned automatic update detection and prompt pages (`check_auto_update` & `trigger_standalone_update_page`) with clear numbered option choices (`[1] Update Tool Now (Recommended)`, `[0] Skip & Continue to Menu`).

## [4.5_beta_9be709c] - 2026-08-09
### Removed
- **Sub-menu Option Emojis**: Complete removal of choice emojis across all sub-menus and update pages (`traffic_monitor_menu`, `service_action_menu`, `uninstall_script`, update pages).

## [4.5_beta_70f7c21] - 2026-08-09
### Added
- **Mandatory Agent UI & Directives**: Established `.gemini/rules/agent_rules.md` and `.gemini/rules/ui_design_rules.md` requiring strict sub-menu unification, icon-free choices, ultra-concise labels, and 7-character Git Commit SHA versioning.
