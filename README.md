# OpenClaw - Self-Hosted Boilerplate

Security-focused, fully automated setup for [OpenClaw](https://openclaw.ai) on any Linux VPS. One script takes a fresh server to a running, hardened instance. No manual steps after it finishes.

---

## Compatibility

| OS family | Tested distros | Firewall used |
|---|---|---|
| Debian / Ubuntu | Ubuntu 22.04+, Debian 11+ | ufw |
| RHEL / Fedora | AlmaLinux 9, Rocky 9, Fedora 38+ | firewalld |

Works on any provider: DigitalOcean, Vultr, Linode, OVH, AWS EC2, bare metal, and others.

**Minimum specs:** 2 vCPU, 4 GB RAM. If your provider offers full disk encryption at provisioning time, enable it before you start.

---

## Quickstart

```bash
ssh root@YOUR_SERVER_IP
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

The script is fully idempotent - re-running it skips steps that are already complete.

---

## What the script does

Each step is skipped automatically if already done.

1. **Fetch and pin checksums** - Downloads the Docker and Tailscale install scripts once to compute their SHA256, then re-downloads them for execution and verifies the hashes match. Aborts on any mismatch.
2. **Install base packages** - Updates the system, installs ufw/firewalld, fail2ban, unattended-upgrades, curl, git, openssl, logrotate.
3. **Create openclaw user** - Dedicated system user with its own home directory. The container and all config run under this user, not root.
4. **Set up SSH key** - Copies from root's `authorized_keys`, reads from `OPENCLAW_SSH_PUBLIC_KEY` env var, or prompts for a paste. Validates key format and rejects multi-line injection.
5. **Harden sshd** - Disables root login, password auth, keyboard-interactive auth, empty passwords, X11/TCP/agent forwarding, and user environment injection. Sets `MaxAuthTries 3`, `LoginGraceTime 20`, idle timeout at 10 minutes, `AllowUsers openclaw`. Uses drop-in files on modern distros.
6. **Configure firewall** - ufw or firewalld: deny all inbound, allow SSH only.
7. **Enable fail2ban** - Started and enabled on boot.
8. **Install Tailscale** - Verified against pinned checksum before execution.
9. **Install Docker** - Verified against pinned checksum. Adds `openclaw` to the docker group.
10. **Clone OpenClaw repo** - Into `/home/openclaw/openclaw`.
11. **Create data directories** - `/home/openclaw/.openclaw/workspace` owned by the openclaw user. Backup dir at `/home/openclaw/backups` owned by root (700).
12. **Generate `.env`** - Two secrets generated via `openssl rand -hex 32`. File is pre-created with correct ownership and `600` permissions before secrets are written.
13. **Write `docker-compose.yml`** - Gateway bound to `127.0.0.1` only, `read_only` filesystem, `no-new-privileges`, `cap_drop: ALL`, memory/CPU/PID limits, log rotation caps, health checks.
14. **Select AI provider** - Interactive menu to choose Anthropic Claude, MiniMax M2.5, GLM-5, or a custom OpenAI-compatible endpoint. API key stored separately in `~/.openclaw/.env` with `600` permissions.
15. **Write `openclaw.json`** - Telegram token read silently (no terminal echo), JSON-sanitized before writing. Model set to the provider chosen above. Secure defaults: loopback bind, token auth, allowlist DM policy, sandbox enabled, mDNS minimal, full sensitive data redaction.
16. **Set up auto-updates** - Installs `openclaw-update.sh` to `/usr/local/bin`, creates `/etc/cron.d/openclaw-update` (Sundays 03:00), configures logrotate (weekly, 12-week retention).
17. **Build and start container** - `docker compose build` then `docker compose up -d`.
18. **Verify gateway binding** - Confirms the gateway is listening on `127.0.0.1:18789`, not `0.0.0.0`.
19. **Run security audit** - Waits for the gateway to be ready, then runs `openclaw doctor` and `openclaw security audit --deep` inside the container automatically. Warns if any issues are found.

---

## Supported AI providers

The setup script asks which AI provider to use. You can change providers at any time by editing `openclaw.json` and `~/.openclaw/.env`.

| Provider | Model | Input / Output (per 1M tokens) | License | Notes |
|---|---|---|---|---|
| Anthropic | `anthropic/claude-opus-4-6` | $5.00 / $25.00 | Proprietary | Strongest prompt injection resistance. Requires commercial API key (not a Pro/Max subscription). |
| MiniMax | `minimax/MiniMax-M2.5` | $0.30 / $1.20 | MIT | Open weights, self-hostable. 80.2% SWE-Bench. 63x cheaper than Claude Opus. |
| Zhipu AI | `zhipu/glm-5` | $0.30 / $2.55 | MIT | Open weights, self-hostable. 77.8% SWE-Bench. Available via 8+ API providers. |
| Custom | Any OpenAI-compatible | Varies | Varies | DeepSeek, Qwen, or any provider with an OpenAI-compatible API. |

MiniMax M2.5 and GLM-5 are recommended if cost is a concern - they deliver competitive agentic performance at a fraction of the price of proprietary models. Both are open-weight and MIT-licensed, meaning you can also self-host them.

---

## After the script finishes

The only things left to do manually:

**1. Authenticate Tailscale**
```bash
tailscale up
```
Follow the printed URL to authenticate your node.

**2. Expose the Control UI**

Via Tailscale (permanent, TLS included):
```bash
tailscale serve https / http://127.0.0.1:18789
```

Via SSH tunnel (one-off from your local machine):
```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@YOUR_SERVER_IP
# Then open http://127.0.0.1:18789/ in your browser
```

**3. Fill in Telegram credentials if you skipped them**
```bash
nano /home/openclaw/.openclaw/openclaw.json
```

---

## Pre-configuration via environment variables

To run fully non-interactively (useful for automation):

```bash
export OPENCLAW_SSH_PUBLIC_KEY="ssh-ed25519 AAAA..."
bash setup.sh
```

Telegram credentials cannot be passed via env var - enter them interactively or edit `openclaw.json` after setup.

---

## Auto-updates

`openclaw-update.sh` runs every Sunday at 03:00 as root. It:

- Acquires an exclusive lock (prevents concurrent runs from corrupting state)
- Creates a timestamped, root-only backup of `/home/openclaw/.openclaw` to `/home/openclaw/backups`
- Prunes backups older than 30 days
- Pulls the latest repo changes and rebuilds the Docker image
- Restarts the container

Logs: `/var/log/openclaw-update.log` (weekly rotation, kept 12 weeks)

Run manually at any time:
```bash
/usr/local/bin/openclaw-update.sh
```

---

## CI pipeline

All GitHub Actions are pinned to immutable commit SHAs to prevent supply chain attacks via tag hijacking.

| Workflow | What it does |
|---|---|
| `lint.yml` | ShellCheck on all `.sh` files (severity: warning) |
| `security.yml` | TruffleHog secret scanning (verified secrets only), Gitleaks secondary scan, Trivy config and filesystem scanning for docker-compose and IaC misconfigurations |
| `test.yml` | Docker-based smoke test that runs `setup.sh` in a simulated VPS and validates every step |

Every job runs behind [StepSecurity Harden-Runner](https://github.com/step-security/harden-runner) to monitor and audit outbound network traffic during CI execution.

---

## Files

| File | Purpose |
|---|---|
| `setup.sh` | Full bootstrap - run as root on a fresh server |
| `openclaw-update.sh` | Weekly auto-update and backup - installed to `/usr/local/bin` |
| `docker-compose.yml` | Docker Compose service definition |
| `.env.example` | Template showing all required env vars |
| `openclaw.json.example` | Template showing all config options with secure defaults |
| `test/Dockerfile.test` | Docker image that simulates a fresh Ubuntu VPS for testing |
| `test/test-setup.sh` | Smoke test that exercises `setup.sh` and validates every step |
| `.gitignore` | Prevents secrets, keys, certs, and backups from being committed |

---

## Security model

| Area | What's done |
|---|---|
| Supply chain | Install scripts checksummed before execution, mismatch aborts. CI actions pinned to SHA. |
| CI scanning | TruffleHog + Gitleaks secret scanning, Trivy config/filesystem scanning, Harden-Runner network monitoring |
| Network | Gateway bound to `127.0.0.1` only - never public |
| Remote access | Tailscale only - no open ports beyond SSH |
| SSH | Key-only, no root login, no password/keyboard-interactive auth, no forwarding, idle timeout 10min, `AllowUsers openclaw` |
| Container | `read_only` filesystem, `no-new-privileges:true`, `cap_drop: ALL`, memory limit 2G, PID limit 256, CPU limit 2.0, log rotation (10M x 3 files), health checks |
| Secrets | Generated fresh per install, `600` permissions, root-owned backups, `umask 077` in all scripts |
| Disk | Provider-level encryption recommended at provisioning |
| Inbound messages | `dmPolicy: allowlist` - only your user ID can DM the agent |
| Sessions | `dmScope: per-channel-peer` - no context leakage between senders |
| Logging | `redactSensitive: tools` - sensitive data redacted in tool outputs. Auth rate limiting (10 attempts/min, 5min lockout) |
| Model | Configurable: Claude Opus 4.6 (default), MiniMax M2.5, GLM-5, or custom. Larger models offer stronger prompt injection resistance. |
| Sandbox | Always enabled, workspace-only access |
| Audit | `openclaw security audit --deep` runs automatically after bootstrap |
| Updates | Weekly automatic with exclusive lock and backup before every update |
| Skills | Install only from trusted sources - read `SKILL.md` before adding any |

---

## Known limitations

The boilerplate hardens the infrastructure around OpenClaw. It cannot eliminate risks that are inherent to running an AI agent with real system access:

- Credentials are stored unencrypted on disk at `/home/openclaw/.openclaw/openclaw.json`. Anyone with shell access as `openclaw` can read them.
- The docker group gives `openclaw` effective root on the host. This is required for Docker to function.
- Prompt injection via crafted messages is a real class of attack. The allowlist, sandbox, and Opus 4.6 model selection reduce the risk but do not eliminate it.
- Third-party skills extend the trust boundary. Only install skills you have read and understand.
