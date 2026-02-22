# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-02-22

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

[Unreleased]: https://github.com/marcelbaklouti/openclaw-boilerplate/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/marcelbaklouti/openclaw-boilerplate/releases/tag/v1.0.0
