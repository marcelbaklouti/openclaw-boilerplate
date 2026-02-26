# QuickStart: Deploy on a VPS (Virtual Private Server)

**Difficulty:** Beginner-friendly
**Time:** About 15–20 minutes
**Cost:** From ~$5/month (DigitalOcean, Vultr, Hetzner, Linode, OVH)

A VPS is a rented Linux server that lives in a data center. You don't own the hardware — you just pay a monthly fee and get full control of the machine over the internet. This is the simplest way to run OpenClaw 24/7.

---

## What you need before you start

- A credit/debit card to sign up with a VPS provider
- An email address
- A computer with a terminal (Mac has one built in, Windows users see the [Windows guide](windows.md))
- 15 minutes

---

## Step 1 — Choose a provider and create a server

Pick any of these — they all work the same way with this guide:

| Provider | Cheapest plan | Link |
|---|---|---|
| **Hetzner** | ~$4/mo (2 vCPU, 4 GB RAM) | hetzner.com |
| **DigitalOcean** | ~$12/mo (2 vCPU, 4 GB RAM) | digitalocean.com |
| **Vultr** | ~$10/mo (2 vCPU, 4 GB RAM) | vultr.com |
| **Linode (Akamai)** | ~$12/mo (2 vCPU, 4 GB RAM) | linode.com |
| **OVH** | ~$7/mo (2 vCPU, 4 GB RAM) | ovhcloud.com |

> **Minimum specs:** 2 vCPU, 4 GB RAM. Pick a plan that meets or exceeds these.

When creating your server:
- **Operating system:** Choose **Ubuntu 22.04 LTS** (or Ubuntu 24.04 LTS)
- **Authentication:** Choose **SSH Key** (more secure than a password) — the provider will walk you through creating one
- **Region:** Pick one close to where you live

After creating the server, you'll see an **IP address** — something like `203.0.113.42`. Copy it, you'll need it in a moment.

---

## Step 2 — Open a terminal on your computer

**Mac:** Press `Cmd + Space`, type `Terminal`, press Enter.

**Windows:** See the [Windows guide](windows.md) to set up WSL first.

**Linux:** You already know how to do this.

---

## Step 3 — Connect to your server

In your terminal, type this (replace `YOUR_SERVER_IP` with your actual IP address):

```bash
ssh root@YOUR_SERVER_IP
```

If this is your first time connecting you'll see a message like:
```
Are you sure you want to continue connecting? yes
```
Type `yes` and press Enter.

You should now see a prompt like `root@ubuntu-server:~#` — you're in!

---

## Step 4 — Run the setup

Copy and paste these three commands one at a time:

```bash
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

The script will now run automatically. It will:
- Install and configure everything needed
- Ask you which AI provider to use (Claude, MiniMax, etc.) — have your API key ready
- Ask which messaging app to connect (Telegram, Discord, WhatsApp, or Slack)
- Set up secure remote access via Tailscale

Just follow the prompts. The whole process takes about 10 minutes.

---

## Step 5 — Access your agent

Once setup finishes, you'll see a success message.

**From the same SSH session** you can open the Control UI immediately at `http://127.0.0.1:18789/` in a browser on the server — but since it's a remote server, you need to tunnel to it first.

**Option A — SSH tunnel (quick, works every time):**

From your local computer (open a new terminal window), run:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@YOUR_SERVER_IP
```

Leave that window open, then go to `http://127.0.0.1:18789/` in your browser.

**Option B — Tailscale (recommended for regular use):**

If you authenticated Tailscale during setup, your Control UI is available at `https://YOUR-MACHINE.tailnet-name.ts.net/` from anywhere in the world — no tunnelling needed.

---

## Common problems

**"Connection refused" when SSHing:**
Wait 30 seconds after the server first boots — it takes a moment to be ready.

**"Permission denied" after setup:**
The script restricts SSH to the `openclaw` user. Try: `ssh openclaw@YOUR_SERVER_IP`

**Forgot the Tailscale step during setup:**
SSH in and run: `tailscale up`

---

## What's next

- [Connect a messaging channel](https://docs.openclaw.ai/channels)
- [Enable the sandbox](../../README.md#after-the-script-finishes)
- [Automatic backups and updates](../../README.md#backup-and-restore)
