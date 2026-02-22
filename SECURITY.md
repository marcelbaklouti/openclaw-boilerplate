# Security Policy

## Reporting a Vulnerability

**Do not open a public issue.**

If you discover a security vulnerability in this project, please report it privately:

1. Go to the [Security Advisories](https://github.com/marcelbaklouti/openclaw-boilerplate/security/advisories) tab
2. Click **"Report a vulnerability"**
3. Provide a clear description, steps to reproduce, and the potential impact

You will receive a response within 72 hours. Once confirmed, a fix will be developed privately and disclosed after a patch is available.

## Scope

This policy covers:

- `setup.sh` and `openclaw-update.sh` (server bootstrap and update logic)
- `docker-compose.yml` (container configuration)
- `.github/workflows/` (CI pipeline)
- `.env.example` and `openclaw.json.example` (config templates)

Out of scope: vulnerabilities in OpenClaw itself, Docker, Tailscale, or other upstream dependencies. Report those to their respective maintainers.

## Supported Versions

Only the latest version on the `main` branch is supported with security updates.
