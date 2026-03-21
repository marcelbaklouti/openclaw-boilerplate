# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0](https://github.com/marcelbaklouti/openclaw-boilerplate/releases/tag/v3.0.0)

### Added

- **OpenAI GPT-5.4 provider**: Added as a first-class provider option in the setup wizard (option 2), alongside Claude Opus 4.6, MiniMax M2.5, GLM-5, and custom endpoints
- **Signal channel**: Added Signal as a built-in channel option in setup (OAuth-based, uses `openclaw channels login`)
- **`tools.profile: full`**: Explicitly set in generated config to prevent the v2026.3.2 bug that defaulted `tools.profile` to `messaging` (which disabled exec/file tools)
- **`plugins.security.autoLoadWorkspace: false`**: Disables implicit workspace plugin auto-load so cloned repositories cannot execute plugin code without explicit trust (v2026.3.13 security hardening)
- **`agents.defaults.thinking: adaptive`**: Enables dynamic cognitive effort scaling based on task complexity (v2026.3.1 default for Claude 4.6 models)
- **`persistBindings: true`**: Added to Telegram and Discord channel configs so channel/topic bindings survive gateway restarts (v2026.3.7 durable binding storage)
- **`OPENCLAW_TZ`**: Docker timezone override in `docker-compose.yml` and `.env.example` to pin gateway containers to a chosen IANA timezone
- **Post-update security audit**: `openclaw-update.sh` now runs `openclaw doctor --fix` and `openclaw security audit --deep` after every weekly update
- **Version logging**: `openclaw-update.sh` now logs the OpenClaw version before and after each update for audit trail
- **New test assertions**: Smoke test validates `tools.profile`, `plugins.security.autoLoadWorkspace`, `agents.defaults.thinking`, and `persistBindings` in generated config

### Changed

- AI provider menu expanded from 4 to 5 options (Anthropic, OpenAI, MiniMax, Zhipu, Custom)
- Channel selection menu expanded from 5 to 6 options (added Signal)
- Security model documentation updated with plugin security, persistent bindings, tool profile, and Cisco research citation

### Security

- Workspace plugin auto-load disabled by default -- prevents supply chain attacks via cloned repos containing malicious workspace plugins
- Explicit `tools.profile: full` prevents silent tool restriction from the v2026.3.2 `messaging` default bug
- Post-update `openclaw security audit --deep` catches regressions introduced by upstream updates
- Added warning about third-party skill risks citing Cisco's AI security research findings

## [2.0.0](https://github.com/marcelbaklouti/openclaw-boilerplate/releases/tag/v2.0.0)

### Added

- Multi-provider AI model selection during setup: Anthropic Claude, MiniMax M2.5, GLM-5, or custom OpenAI-compatible endpoints
- API key stored in `~/.openclaw/.env` (600 permissions) separate from runtime config
- `test/Dockerfile.test` and `test/test-setup.sh`: Docker-based smoke test for setup.sh
- `test.yml` workflow: runs the smoke test on every push and PR to `main`
- Release workflow verifies all required CI workflows passed before running release-please
- Multi-channel support: Telegram, Discord, WhatsApp, Slack with interactive selection during setup
- Tailscale access automation: `tailscale up` and `tailscale serve` integrated into setup flow
- `openclaw onboard` wizard integration for OAuth channels (WhatsApp, Slack)
- Node.js 22 LTS installation via NodeSource as part of setup (OpenClaw prerequisite)
- `openclaw-restore.sh`: interactive backup restore with integrity validation and pre-restore snapshots
- Daily npm security update cron (`/etc/cron.d/openclaw-npm-security`, 02:00)
- `gateway.mode: local` in generated config per docs hardened baseline
- `gateway.auth.allowTailscale: true` for Tailscale Serve identity-header auth
- `tools.fs.workspaceOnly: true` and `tools.elevated.enabled: false` security baseline
- `session.reset` config for daily automatic context resets (04:00, 120min idle)
- Group chat mention gating (`requireMention: true`) on all channels
- Control UI availability note in post-setup output (works without any channel)
- `openclaw configure`, `openclaw config set`, `openclaw doctor --fix` mentioned in post-setup help

### Changed

- **Architecture**: replaced `git clone` + custom `docker-compose.yml` + custom `.env` with official OpenClaw installer (`https://openclaw.ai/install.sh`) + `openclaw onboard --install-daemon`. The boilerplate now wraps official tooling with server hardening.
- `dmPolicy` changed from `allowlist` to `pairing` for all channels (docs-recommended default). Pre-seeded allowlist still applies for configured user IDs.
- `sandbox.mode` changed from `all` to `off` (sandbox image not built during setup). Instructions to enable post-install included.
- `openclaw-update.sh` now uses `npm update -g openclaw@latest` + `systemctl restart` instead of `git pull` + `docker compose build`
- `openclaw doctor` now runs with `--fix` flag for auto-repair
- Checksum fetches are skipped for tools that are already installed
- Security audit and onboard wizard now call `openclaw` directly instead of via `docker exec`

### Fixed

- `setup.sh`: remove invalid `--permanent` flag from `firewall-cmd --set-default-zone` which broke setup on all RHEL/Fedora systems
- `setup.sh`: prepend `tg:` prefix to Telegram user ID in generated `openclaw.json`
- Discord config: changed `botToken` to `token` (correct field name per docs configuration reference)
- `release.yml`: gate releases on all required workflows passing

## [1.0.0](https://github.com/marcelbaklouti/openclaw-boilerplate/releases/tag/v1.0.0) (2026-02-22)

### Added

- MIT license
- `SECURITY.md` with private vulnerability reporting instructions
- `CODEOWNERS` requiring review on all security-sensitive files
- `.github/dependabot.yml` for weekly GitHub Actions SHA updates
- `.editorconfig` enforcing consistent formatting (LF, UTF-8, 2-space indent)
- `CHANGELOG.md` following Keep a Changelog format
- `setup.sh`: full server bootstrap (user creation, SSH hardening, firewall, Docker, Tailscale, config generation, container build, security audit)
- `openclaw-update.sh`: weekly auto-update with backup, pruning, rebuild
- `docker-compose.yml`: hardened single-service container definition
- `.env.example` and `openclaw.json.example`: config templates with secure defaults
- `lint.yml` workflow: ShellCheck on all shell scripts
- `security.yml` workflow: TruffleHog secret scanning, Gitleaks secondary scan, Trivy config and filesystem scanning
- StepSecurity Harden-Runner on all CI jobs to audit outbound network traffic
- `gateway.auth.rateLimit` in config: 10 attempts per 60s, 5-minute lockout on brute-force
- Container health check (HTTP probe every 30s with 15s startup grace)
- Container resource limits: 2G memory, 2.0 CPU, 256 PID cap, log rotation (10M x 3)
- `read_only: true` container filesystem with tmpfs for `/tmp` and `/home/node/.npm`
- `flock`-based mutual exclusion in `openclaw-update.sh` to prevent concurrent runs
- `umask 077` in all shell scripts for secure default file permissions
- `trap ... RETURN` cleanup for all temp files in `setup.sh`
- SSH hardening: key-only auth, no root login, no forwarding, no empty passwords, idle timeout 10min, `AllowUsers openclaw`
- `.gitignore` patterns for private keys, certs, editor artifacts, extra env files
- Multi-line SSH key injection rejection in `validate_ssh_public_key`
- Supply chain verification: double-fetch SHA256 checksums for Docker and Tailscale install scripts
- All CI actions pinned to immutable commit SHAs
- `permissions: contents: read` on all CI workflows (least privilege)

### Security

- All CI actions pinned to SHA to prevent supply chain attacks via tag hijacking
- Harden-Runner detects and audits outbound network calls during CI
- TruffleHog scans full git history for verified active secrets
- Gitleaks provides secondary regex-based secret detection on every push/PR
- Trivy scans docker-compose.yml and repo filesystem for misconfigurations and vulnerabilities
- Auth rate limiting prevents brute-force gateway token guessing
- Container resource limits prevent DoS via memory exhaustion, fork bombs, or CPU starvation
- Immutable container filesystem prevents persistent malware
- Idle SSH sessions killed after 10 minutes
- Concurrent update prevention via flock avoids state corruption

