# Contributing

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/) and [release-please](https://github.com/googleapis/release-please) for automated versioning and changelog generation.

Every commit to `main` must follow this format:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types and version impact

| Prefix | Version bump | Example |
|---|---|---|
| `fix:` | Patch (1.0.0 -> 1.0.1) | `fix: SC2155 shellcheck warning` |
| `feat:` | Minor (1.0.0 -> 1.1.0) | `feat: add kernel sysctl hardening` |
| `feat!:` or footer `BREAKING CHANGE:` | Major (1.0.0 -> 2.0.0) | `feat!: restructure env var names` |
| `chore:`, `ci:`, `docs:`, `test:`, `build:`, `style:` | No release | `ci: bump actions/checkout` |
| `refactor:`, `perf:` | Patch (appears in changelog under "Changed") | `refactor: simplify backup rotation` |
| `security:` | Patch (appears under "Security") | `security: restrict SSH ciphers` |

### How releases work

1. Push commits to `main` using the prefixes above
2. release-please automatically opens a **Release PR** that bumps the version in `.release-please-manifest.json`, updates `CHANGELOG.md`, and creates `version.txt`
3. Review and merge the Release PR
4. release-please tags `vX.Y.Z` and creates a GitHub Release with auto-generated notes

You can also trigger a release manually from the Actions tab via `workflow_dispatch`.

### Scopes (optional)

Scopes add context but don't affect versioning:

```
fix(ssh): reject multi-line key injection
feat(gateway): add IP allowlist
ci(deps): bump actions/checkout from v6.0.2 to v6.0.3
```

## Branch Naming

Use a descriptive prefix matching the commit type:

```
fix/sc2155-shellcheck-warning
feat/kernel-sysctl-hardening
security/restrict-ssh-ciphers
ci/add-hadolint-workflow
chore/project-governance
```

## Pull Requests

- Branch off `main`
- Keep PRs focused on a single concern
- All CI checks must pass before merge (see [CI Pipeline](#ci-pipeline))
- Security-sensitive files require CODEOWNERS review (see below)
- Squash merge is preferred to keep `main` history clean for release-please

### CODEOWNERS

All files are owned by `@marcelbaklouti`. The following files are explicitly listed for mandatory review:

- `setup.sh`, `openclaw-update.sh`, `docker-compose.yml`
- `.env.example`, `openclaw.json.example`
- Everything under `.github/`

## Project Structure

| File | Purpose |
|---|---|
| `setup.sh` | Full server bootstrap, run as root on a fresh VPS |
| `openclaw-update.sh` | Weekly auto-update with backup and exclusive locking |
| `docker-compose.yml` | Hardened container definition for the OpenClaw gateway |
| `.env.example` | Template for all required environment variables |
| `openclaw.json.example` | OpenClaw runtime config with secure defaults |
| `.github/workflows/lint.yml` | ShellCheck on all `.sh` files |
| `.github/workflows/security.yml` | TruffleHog, Gitleaks, Trivy config + filesystem scans |
| `.github/workflows/release.yml` | release-please for automated versioning and GitHub Releases |
| `.github/workflows/dependabot-auto-merge.yml` | Auto-merge non-major Dependabot PRs after CI passes |
| `.github/dependabot.yml` | Weekly SHA updates for GitHub Actions |
| `release-please-config.json` | Changelog sections and release-type config |
| `.release-please-manifest.json` | Current version tracker (updated automatically) |
| `CHANGELOG.md` | Release history (managed by release-please going forward) |
| `SECURITY.md` | Vulnerability reporting instructions |
| `CODEOWNERS` | Mandatory reviewers for security-sensitive files |
| `.editorconfig` | Formatting enforcement |
| `.gitignore` | Prevents secrets, keys, backups, and editor artifacts from being committed |
| `LICENSE` | MIT |

## CI Pipeline

Every push and PR to `main` runs:

| Workflow | Tool | What it checks |
|---|---|---|
| `lint.yml` | ShellCheck | All `.sh` files at `warning` severity |
| `security.yml` | TruffleHog | Full git history for verified active secrets |
| `security.yml` | Gitleaks | Secondary regex-based secret detection |
| `security.yml` | Trivy (config) | `docker-compose.yml` and IaC misconfigurations |
| `security.yml` | Trivy (filesystem) | Repo files for known vulnerabilities |

Every job runs behind [StepSecurity Harden-Runner](https://github.com/step-security/harden-runner) to audit outbound network traffic during CI.

## Adding or Updating GitHub Actions

All actions **must** be pinned to an immutable commit SHA, not a tag. Tags can be force-pushed; SHAs cannot.

```yaml
# correct
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

# wrong
- uses: actions/checkout@v4
```

Always add a trailing comment with the human-readable version for auditability. Dependabot handles SHA updates automatically via weekly PRs.

## Dependabot Auto-Merge

Dependabot opens PRs for GitHub Actions SHA bumps every Monday. If CI passes:

- **Patch and minor** updates are auto-approved and squash-merged
- **Major** updates stay open for manual review

Dependabot commits use the `ci(deps):` prefix, which is hidden in the changelog and does not trigger a release.

## Code Style

- Shell scripts: follow [ShellCheck](https://www.shellcheck.net/) at `warning` severity or above
- No comments that just narrate what the code does
- `umask 077` at the top of every new shell script
- Use `printf` over `echo` for anything containing variables
- Separate `local` declarations from command-substitution assignments (SC2155)
- Use `trap` for cleanup of temporary files
- YAML/JSON: 2-space indent, UTF-8, LF line endings (enforced by `.editorconfig`)
- Markdown: trailing whitespace is preserved (`.editorconfig` exemption)
- Makefiles: tab indentation

## Container Hardening Rules

When modifying `docker-compose.yml`, preserve these constraints:

- `read_only: true` with explicit `tmpfs` mounts for writable paths
- `cap_drop: ALL` with no `cap_add` (gateway runs on port > 1024)
- `no-new-privileges:true`
- Memory, swap, PID, and CPU limits
- Log rotation (`max-size` + `max-file`)
- Health check present and functional
- Gateway bound to `127.0.0.1` only, never `0.0.0.0`

## Secrets and Environment

- `.env` and `openclaw.json` are gitignored and must never be committed
- `.env.example` and `openclaw.json.example` are safe to commit (they contain placeholder values only)
- Generate secrets with `openssl rand -hex 32`
- All secret files must be `chmod 600` and owned by the appropriate user

## Testing Changes Locally

There is no test suite. Validate changes by:

1. Running ShellCheck locally: `shellcheck setup.sh openclaw-update.sh`
2. Reviewing `docker compose config` for valid compose output
3. Testing `setup.sh` on a fresh VM (DigitalOcean droplets or Multipass work well)
4. Verifying the gateway starts and binds correctly after any container changes

## Security

If you find a vulnerability, do **not** open a public issue. See [SECURITY.md](SECURITY.md) for responsible disclosure instructions.
