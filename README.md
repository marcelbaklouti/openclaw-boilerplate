# OpenClaw - Self-Hosted Boilerplate

Security-focused, fully automated setup for [OpenClaw](https://openclaw.ai) on any Linux VPS. One script takes a fresh server to a running, hardened instance with your chosen messaging channel connected and the Control UI accessible via Tailscale.

Uses the official OpenClaw installer and `openclaw onboard` wizard -- this boilerplate adds server hardening, automated backups, and security update infrastructure around the official tooling.

---

## Deployment Guides

New to self-hosting? These step-by-step guides walk you through every platform in plain language — no Linux experience required.

| Platform | Guide | Notes |
|---|---|---|
| **VPS** (DigitalOcean, Hetzner, Vultr, Linode, OVH...) | [docs/quickstart/vps.md](docs/quickstart/vps.md) | Easiest starting point, ~$5/month |
| **AWS EC2** | [docs/quickstart/aws.md](docs/quickstart/aws.md) | Amazon cloud, larger ecosystem |
| **Own server at home** | [docs/quickstart/home-server.md](docs/quickstart/home-server.md) | Old PC or mini PC, runs 24/7 on your hardware |
| **Raspberry Pi** | [docs/quickstart/raspberry-pi.md](docs/quickstart/raspberry-pi.md) | Tiny, silent, low-power home server |
| **Docker** | [docs/quickstart/docker.md](docs/quickstart/docker.md) | Containerised deploy with docker-compose |
| **Mac** (Lume / UTM / OrbStack) | [docs/quickstart/mac.md](docs/quickstart/mac.md) | Run a Linux VM on your Mac |
| **Windows** (WSL2) | [docs/quickstart/windows.md](docs/quickstart/windows.md) | Linux inside Windows |

---

## Compatibility

| OS family       | Tested distros                   | Firewall used |
| --------------- | -------------------------------- | ------------- |
| Debian / Ubuntu | Ubuntu 22.04+, Debian 11+        | ufw           |
| RHEL / Fedora   | AlmaLinux 9, Rocky 9, Fedora 38+ | firewalld     |

Works on any provider: DigitalOcean, Vultr, Linode, OVH, AWS EC2, bare metal, and others.

**Minimum specs:** 2 vCPU, 4 GB RAM, Node.js 22+ (installed automatically). If your provider offers full disk encryption at provisioning time, enable it before you start.

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

1. **Fetch and pin checksums** -- Downloads the Docker, Tailscale, and OpenClaw install scripts once to compute their SHA256, then re-downloads them for execution and verifies the hashes match. Aborts on any mismatch. Skipped for tools already installed.
2. **Install base packages** -- Updates the system, installs ufw/firewalld, fail2ban, unattended-upgrades/dnf-automatic, curl, git, openssl, logrotate.
3. **Create openclaw user** -- Dedicated system user with its own home directory. All config and data live under this user.
4. **Set up SSH key** -- Copies from root's `authorized_keys`, reads from `OPENCLAW_SSH_PUBLIC_KEY` env var, or prompts for a paste. Validates key format and rejects multi-line injection.
5. **Harden sshd** -- Disables root login, password auth, keyboard-interactive auth, empty passwords, X11/TCP/agent forwarding, and user environment injection. Sets `MaxAuthTries 3`, `LoginGraceTime 20`, idle timeout at 10 minutes, `AllowUsers openclaw`. Uses drop-in files on modern distros.
6. **Configure firewall** -- ufw or firewalld: deny all inbound, allow SSH only.
7. **Enable fail2ban** -- Started and enabled on boot.
8. **Install Tailscale** -- Verified against pinned checksum before execution.
9. **Install Docker** -- Verified against pinned checksum. Adds `openclaw` to the docker group (needed for sandbox).
10. **Install Node.js 22 LTS** -- Via NodeSource repository, verified against pinned checksum before execution. Included in OS auto-updates for security patches.
11. **Install OpenClaw** -- Via the official installer script (`https://openclaw.ai/install.sh`), verified against pinned checksum.
12. **Create data directories** -- `/home/openclaw/.openclaw/workspace` owned by the openclaw user. Backup dir at `/home/openclaw/backups` owned by root (700).
13. **Select AI provider** -- Interactive menu to choose Anthropic Claude, OpenAI GPT-5.4, MiniMax M2.5, GLM-5, or a custom OpenAI-compatible endpoint. API key stored in `~/.openclaw/.env` with `600` permissions.
14. **Select messaging channel** -- Choose Telegram, Discord, WhatsApp, Slack, Signal, or none. Telegram and Discord credentials are collected inline; WhatsApp, Slack, and Signal trigger the `openclaw channels login` wizard after the daemon starts. Additional channels (Microsoft Teams, Matrix, Mattermost, IRC, and more) can be added after install via plugins -- see the [channel docs](https://docs.openclaw.ai/channels).
15. **Write `openclaw.json`** -- Hardened config with: `gateway.mode: local`, loopback bind, token + Tailscale auth, device auth enforced, `dmPolicy: pairing` with pre-seeded allowlist, `requireMention` group gating, `tools.profile: full`, `tools.exec.ask: always`, `tools.fs.workspaceOnly`, `tools.elevated.enabled: false`, `browser.enabled: false`, `plugins.security.autoLoadWorkspace: false`, `agents.defaults.thinking: adaptive`, `persistBindings: true` on Telegram/Discord, `sandbox.mode: off` (enable post-install), daily session resets with 30-day maintenance pruning, mDNS minimal, full sensitive data redaction.
16. **Set up auto-updates** -- Installs `openclaw-update.sh` to `/usr/local/bin` (weekly, Sundays 03:00). Adds daily npm security update cron (02:00). Configures logrotate (weekly, 12-week retention).
17. **Start OpenClaw daemon** -- Runs `openclaw onboard --install-daemon` to install as a systemd service.
18. **Verify gateway binding** -- Confirms the gateway is listening on `127.0.0.1:18789`, not `0.0.0.0`.
19. **Run security audit** -- Runs `openclaw doctor --fix` and `openclaw security audit --deep` automatically.
20. **Configure Tailscale access** -- Optionally runs `tailscale up` and `tailscale serve` to expose the Control UI with TLS via your Tailscale network.
21. **Run onboard wizard** -- For OAuth-based channels (WhatsApp, Slack), runs `openclaw channels login --channel <channel>` to complete authentication.

---

## Supported AI providers

The setup script asks which AI provider to use. You can change providers at any time via `openclaw configure` or by editing `openclaw.json`.

| Provider  | Model                       | Input / Output (per 1M tokens) | License     | Notes                                                                                            |
| --------- | --------------------------- | ------------------------------ | ----------- | ------------------------------------------------------------------------------------------------ |
| Anthropic | `anthropic/claude-opus-4-6` | $5.00 / $25.00                 | Proprietary | Strongest prompt injection resistance. Requires commercial API key (not a Pro/Max subscription). |
| OpenAI    | `openai/gpt-5.4`            | Varies                         | Proprietary | Latest OpenAI flagship model. Also available as `openai/gpt-5.4-pro`.                            |
| MiniMax   | `minimax/MiniMax-M2.5`      | $0.30 / $1.20                  | MIT         | Open weights, self-hostable. 80.2% SWE-Bench. 63x cheaper than Claude Opus.                      |
| Zhipu AI  | `zhipu/glm-5`               | $0.30 / $2.55                  | MIT         | Open weights, self-hostable. 77.8% SWE-Bench. Available via 8+ API providers.                    |
| Custom    | Any OpenAI-compatible       | Varies                         | Varies      | DeepSeek, Qwen, or any provider with an OpenAI-compatible API.                                   |

MiniMax M2.5 and GLM-5 are recommended if cost is a concern -- they deliver competitive agentic performance at a fraction of the price of proprietary models. Both are open-weight and MIT-licensed, meaning you can also self-host them.

---

## After the script finishes

The Control UI is immediately available at `http://127.0.0.1:18789/` -- no channel setup needed. You can chat with your agent there right away.

If you chose to authenticate Tailscale and expose the Control UI during setup, remote access is already working. Otherwise:

**1. Authenticate Tailscale** (if skipped during setup)

```bash
tailscale up
tailscale serve https / http://127.0.0.1:18789
```

**Alternative: SSH tunnel** (one-off from your local machine)

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@YOUR_SERVER_IP
```

**2. Fill in channel credentials if you skipped them**

```bash
nano /home/openclaw/.openclaw/openclaw.json
```

**3. Reconfigure at any time**

```bash
openclaw configure
openclaw config set channels.telegram.enabled true
openclaw channels login --channel whatsapp   # OAuth channels (WhatsApp, Slack, Teams, etc.)
openclaw channels list                       # show all configured channels
openclaw channels status                     # check runtime status
openclaw doctor --fix
```

**4. Enable sandbox** (off by default since the sandbox image is not built during setup)

```bash
scripts/sandbox-setup.sh
openclaw config set agents.defaults.sandbox.mode all
```

---

## Pre-configuration via environment variables

To run fully non-interactively (useful for automation):

```bash
export OPENCLAW_SSH_PUBLIC_KEY="ssh-ed25519 AAAA..."
export OPENCLAW_CHANNEL=telegram
export OPENCLAW_TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
export OPENCLAW_TELEGRAM_USER_ID="987654321"
export OPENCLAW_SKIP_TAILSCALE_AUTH=1
bash setup.sh
```

| Variable                       | Purpose                                                                     |
| ------------------------------ | --------------------------------------------------------------------------- |
| `OPENCLAW_SSH_PUBLIC_KEY`      | SSH public key for the openclaw user                                        |
| `OPENCLAW_CHANNEL`             | Channel to configure: `telegram`, `discord`, `whatsapp`, `slack`, `signal`, or `none` |
| `OPENCLAW_TELEGRAM_BOT_TOKEN`  | Telegram bot token (skips interactive prompt)                               |
| `OPENCLAW_TELEGRAM_USER_ID`    | Telegram user ID (skips interactive prompt)                                 |
| `OPENCLAW_DISCORD_BOT_TOKEN`   | Discord bot token (skips interactive prompt)                                |
| `OPENCLAW_DISCORD_USER_ID`     | Discord user ID (skips interactive prompt)                                  |
| `OPENCLAW_SKIP_TAILSCALE_AUTH` | Set to any value to skip Tailscale authentication                           |
| `OPENCLAW_SKIP_ONBOARD`        | Set to any value to skip the onboard wizard for OAuth channels              |

---

## Auto-updates and security patches

### OS-level security patches (daily, automatic)

`unattended-upgrades` (Debian/Ubuntu) or `dnf-automatic` (RHEL/Fedora) apply security updates daily, including Node.js packages from the NodeSource repository.

### npm security updates (daily, 02:00)

A cron job at `/etc/cron.d/openclaw-npm-security` updates npm itself daily.

### OpenClaw updates (weekly, Sundays 03:00)

`openclaw-update.sh` runs every Sunday at 03:00 as root. It:

- Acquires an exclusive lock (prevents concurrent runs)
- Creates a timestamped, root-only backup of `/home/openclaw/.openclaw`
- Prunes backups older than 30 days
- Updates OpenClaw via `npm update -g openclaw@latest`
- Restarts the gateway daemon

Logs: `/var/log/openclaw-update.log` (weekly rotation, kept 12 weeks)

Run manually at any time:

```bash
/usr/local/bin/openclaw-update.sh
```

---

## Backup and restore

### Automatic backups

A full backup of `~/.openclaw` (config, sessions, workspace) is created before every weekly update. Backups are stored at `/home/openclaw/backups/` with root-only permissions (600) and 30-day retention.

### Manual backup

```bash
tar -czf /home/openclaw/backups/manual-$(date +%Y%m%d).tar.gz /home/openclaw/.openclaw
```

### Restore from backup

```bash
/usr/local/bin/openclaw-restore.sh
```

The restore script:

1. Lists all available backups with sizes and dates
2. Validates the selected backup's integrity
3. Stops the gateway
4. Saves a pre-restore snapshot of the current state
5. Restores files and fixes permissions
6. Restarts the gateway

To restore a specific backup without the interactive menu:

```bash
/usr/local/bin/openclaw-restore.sh openclaw-backup-20260222-030000.tar.gz
```

---

## CI pipeline

All GitHub Actions are pinned to immutable commit SHAs to prevent supply chain attacks via tag hijacking.

| Workflow       | What it does                                                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `lint.yml`     | ShellCheck on all `.sh` files (severity: warning)                                                                                           |
| `security.yml` | TruffleHog secret scanning (verified secrets only), Gitleaks secondary scan, Trivy config and filesystem scanning for IaC misconfigurations |
| `test.yml`     | Docker-based smoke test that runs `setup.sh` in a simulated VPS and validates every step                                                    |

Every job runs behind [StepSecurity Harden-Runner](https://github.com/step-security/harden-runner) to monitor and audit outbound network traffic during CI execution.

---

## Files

| File                    | Purpose                                                         |
| ----------------------- | --------------------------------------------------------------- |
| `setup.sh`              | Full bootstrap -- run as root on a fresh server                 |
| `openclaw-update.sh`    | Weekly auto-update with backup and npm upgrade                  |
| `openclaw-restore.sh`   | Interactive backup restore with integrity validation            |
| `openclaw.json.example` | Template showing all config options with secure defaults        |
| `test/Dockerfile.test`  | Docker image that simulates a fresh Ubuntu VPS for testing      |
| `test/test-setup.sh`    | Smoke test that exercises `setup.sh` and validates every step   |
| `.gitignore`            | Prevents secrets, keys, certs, and backups from being committed |

---

## Security model

| Area             | What's done                                                                                                                                                        |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Supply chain     | All install scripts (Docker, Tailscale, Node.js, OpenClaw) consistency-verified before execution: each script is downloaded twice and both hashes compared — mismatch aborts. CI actions pinned to immutable SHAs.                                            |
| CI scanning      | TruffleHog + Gitleaks secret scanning, Trivy config/filesystem scanning, Harden-Runner network monitoring                                                          |
| Network          | Gateway bound to `127.0.0.1` only -- never public. `gateway.mode: local` enforced.                                                                                 |
| Remote access    | Tailscale setup automated during install -- no open ports beyond SSH. `allowTailscale: true` enables identity-header auth.                                         |
| SSH              | Key-only, no root login, no password/keyboard-interactive/host-based auth, no forwarding, idle timeout 10min, `AllowUsers openclaw`. Config tested with `sshd -t` before daemon restart; rolls back on failure.                                              |
| Secrets          | Generated fresh per install, `600` permissions, root-owned backups, `umask 077` in all scripts                                                                     |
| Disk             | Provider-level encryption recommended at provisioning                                                                                                              |
| Channels         | Telegram, Discord, WhatsApp, Slack, Signal supported out of the box. Teams, Matrix, Mattermost, IRC, and 15+ others available as plugins. OAuth channels use `openclaw channels login`.                                                                        |
| Inbound messages | `dmPolicy: pairing` -- unknown senders get a one-time approval code. Pre-seeded allowlist for configured user IDs.                                                 |
| Group chats      | `requireMention: true` on all channels -- bot only responds when @mentioned in groups                                                                              |
| Sessions         | `dmScope: per-channel-peer` -- no context leakage between senders. Daily auto-reset after 120min idle.                                                             |
| Tools            | `tools.profile: full` (explicit -- avoids the v2026.3.2 `messaging` default bug). `exec.ask: always` (approval required for every shell command). `fs.workspaceOnly: true`, `elevated.enabled: false` -- restricted filesystem and no privilege escalation |
| Browser          | `browser.enabled: false` -- browser automation disabled by default. Enable only if needed and with `ssrfPolicy.dangerouslyAllowPrivateNetwork: false` |
| Device auth      | `controlUi.dangerouslyDisableDeviceAuth: false` -- device pairing enforced for Control UI access |
| Sessions         | `session.maintenance.mode: enforce` with 30-day prune and 500 entry cap -- prevents unbounded disk growth from long-running agents |
| Plugins          | `plugins.security.autoLoadWorkspace: false` -- prevents cloned repositories from auto-executing workspace plugin code without explicit trust decision (v2026.3.13 security hardening) |
| Logging          | `redactSensitive: tools` -- sensitive data redacted in tool outputs. Auth rate limiting (10 attempts/min, 5min lockout)                                            |
| Model            | Configurable: Claude Opus 4.6 (default), GPT-5.4, MiniMax M2.5, GLM-5, or custom. Larger models offer stronger prompt injection resistance. `thinking: adaptive` for dynamic cognitive scaling. |
| Sandbox          | Off by default (image not built). Enable post-install with `scripts/sandbox-setup.sh`.                                                                             |
| Audit            | `openclaw doctor --fix` and `openclaw security audit --deep` run automatically after bootstrap and after every weekly auto-update                                  |
| Updates          | Weekly OpenClaw update with version logging, daily npm security update, daily OS security patches via unattended-upgrades/dnf-automatic. Exclusive lock and backup before every update. |
| Backup           | Automatic pre-update backups with 30-day retention. Restore script included.                                                                                       |
| Skills           | Install only from trusted sources -- read `SKILL.md` before adding any. Workspace plugin auto-load is disabled.                                                   |
| Bindings         | `persistBindings: true` on Telegram/Discord -- channel and topic bindings survive gateway restarts (v2026.3.7+)                                                    |

---

## Known limitations

The boilerplate hardens the infrastructure around OpenClaw. It cannot eliminate risks that are inherent to running an AI agent with real system access:

- Credentials are stored unencrypted on disk at `/home/openclaw/.openclaw/openclaw.json`. Anyone with shell access as `openclaw` can read them.
- The docker group gives `openclaw` effective root on the host. This is required for Docker to function (needed for sandbox).
- Prompt injection via crafted messages is a real class of attack. The pairing policy, mention gating, sandbox, and Opus 4.6 model selection reduce the risk but do not eliminate it.
- Third-party skills extend the trust boundary. Only install skills you have read and understand. [Cisco's research](https://www.nxcode.io/resources/news/openclaw-complete-guide-2026) found that unvetted skills can perform data exfiltration and prompt injection.
- Workspace plugins are disabled by default (`plugins.security.autoLoadWorkspace: false`). Do not enable auto-load unless you trust every repository you clone into the workspace.
