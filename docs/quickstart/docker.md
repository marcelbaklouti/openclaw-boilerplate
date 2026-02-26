# QuickStart: Deploy with Docker

**Difficulty:** Intermediate (assumes you have Docker installed)
**Time:** About 15 minutes
**Works on:** Any Linux server, Mac (with a Linux VM), or Windows (with WSL2)

Docker packages OpenClaw and all its dependencies into a container — a sealed box that runs the same way on any machine. The included `docker-compose.yml` takes care of all the security hardening (read-only filesystem, memory limits, no root, etc.).

> **New to Docker?** If you've never used Docker before, the [VPS guide](vps.md) uses the standard install method which is simpler. Docker is best if you already have a server running Docker and want to add OpenClaw to it.

---

## What you need before you start

- A Linux server (or Mac/Windows with Docker Desktop)
- Docker and Docker Compose installed
- The OpenClaw Docker image (available from the [official OpenClaw registry](https://docs.openclaw.ai/install/docker))

---

## Step 1 — Install Docker (if not already installed)

**On Ubuntu/Debian:**

```bash
curl -fsSL https://get.docker.com | bash
```

**On Mac:** Download [Docker Desktop](https://www.docker.com/products/docker-desktop/) and install it like a normal Mac app.

**On Windows:** See the [Windows guide](windows.md), then install Docker Desktop.

Verify Docker is running:
```bash
docker --version
docker compose version
```

---

## Step 2 — Get the repository

```bash
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
```

---

## Step 3 — Set up your environment file

Copy the example `.env` file and fill in your values:

```bash
cp .env.example .env
nano .env
```

You need to fill in:

```bash
# The OpenClaw Docker image (check docs.openclaw.ai/install/docker for the latest)
OPENCLAW_IMAGE=openclaw:latest

# Generate a secure random token (copy the output of this command):
# openssl rand -hex 32
OPENCLAW_GATEWAY_TOKEN=PASTE_YOUR_TOKEN_HERE

# Keep these as-is for a secure setup
OPENCLAW_GATEWAY_BIND=loopback
OPENCLAW_GATEWAY_PORT=18789

# Paths where OpenClaw stores its data
OPENCLAW_CONFIG_DIR=/home/openclaw/.openclaw
OPENCLAW_WORKSPACE_DIR=/home/openclaw/.openclaw/workspace

# Generate another random token for keyring (copy output of openssl rand -hex 32)
GOG_KEYRING_PASSWORD=PASTE_ANOTHER_TOKEN_HERE
XDG_CONFIG_HOME=/home/node/.openclaw
```

To generate a secure token, run:
```bash
openssl rand -hex 32
```

Run it twice and paste the first output into `OPENCLAW_GATEWAY_TOKEN` and the second into `GOG_KEYRING_PASSWORD`.

---

## Step 4 — Create the data directories

```bash
sudo mkdir -p /home/openclaw/.openclaw/workspace
sudo chown -R 1000:1000 /home/openclaw/.openclaw
```

---

## Step 5 — Configure OpenClaw

Create the config file:

```bash
sudo mkdir -p /home/openclaw/.openclaw
sudo cp openclaw.json.example /home/openclaw/.openclaw/openclaw.json
sudo nano /home/openclaw/.openclaw/openclaw.json
```

At minimum, set your AI provider and messaging channel. See the [openclaw.json.example](../../openclaw.json.example) for all options, or run the interactive setup wizard instead (see Step 6b).

Also create the API key file:
```bash
sudo touch /home/openclaw/.openclaw/.env
sudo chmod 600 /home/openclaw/.openclaw/.env
sudo nano /home/openclaw/.openclaw/.env
```

Add your AI provider API key:
```bash
# Pick ONE of these:
ANTHROPIC_API_KEY=sk-ant-...
# MINIMAX_API_KEY=...
# ZHIPU_API_KEY=...
# OPENAI_API_KEY=...
```

---

## Step 6 — Start OpenClaw

```bash
docker compose up -d
```

This starts OpenClaw in the background. Check that it's running:

```bash
docker compose ps
docker compose logs -f
```

You should see `healthy` in the status after about 30 seconds.

**Step 6b — Run the interactive wizard instead:**

If you want to configure channels interactively (like the `setup.sh` does), you can run the onboard wizard inside the container:

```bash
docker compose exec openclaw-gateway openclaw onboard
```

---

## Step 7 — Access the Control UI

The gateway is bound to `127.0.0.1:18789` for security. Access it via SSH tunnel:

```bash
ssh -N -L 18789:127.0.0.1:18789 YOUR_USER@YOUR_SERVER_IP
```

Then open `http://127.0.0.1:18789/` in your browser.

Or use Tailscale for permanent remote access:
```bash
tailscale serve https / http://127.0.0.1:18789
```

---

## Useful Docker commands

```bash
# Stop OpenClaw
docker compose down

# Restart OpenClaw
docker compose restart

# View live logs
docker compose logs -f

# Update to a new version
docker compose pull
docker compose up -d

# Back up your config
tar -czf openclaw-backup-$(date +%Y%m%d).tar.gz /home/openclaw/.openclaw
```

---

## Common problems

**"Cannot connect to the Docker daemon":**
The Docker service isn't running. Start it: `sudo systemctl start docker`

**Container keeps restarting:**
Check the logs: `docker compose logs --tail=50`. Usually a missing or incorrect value in `.env` or `openclaw.json`.

**"Error: image not found":**
Make sure `OPENCLAW_IMAGE` in `.env` points to the correct image name. Check [docs.openclaw.ai/install/docker](https://docs.openclaw.ai/install/docker) for the official image name.

---

## What's next

- [Connect a messaging channel](https://docs.openclaw.ai/channels)
- [Enable the sandbox](../../README.md#after-the-script-finishes)
- [Automatic backups and updates](../../README.md#backup-and-restore)
