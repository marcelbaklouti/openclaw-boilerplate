# QuickStart: Deploy on Your Own Server at Home

**Difficulty:** Intermediate (you'll be configuring your home network)
**Time:** 30–60 minutes
**Cost:** Just electricity (~$5–15/month depending on your hardware)

Running OpenClaw on a server at home means your data never leaves your house and you have no monthly hosting fee. The trade-off is that you'll need to manage the hardware yourself.

---

## What you need before you start

- A spare computer, old laptop, or mini PC with at least **2 CPU cores and 4 GB RAM**
- An ethernet cable (Wi-Fi works but wired is more reliable for a server)
- Access to your home router's admin page (to set up port forwarding — optional but useful)
- About an hour to get everything set up

> **Good hardware options for a home server:**
> - Any PC from the last 10 years with 4+ GB RAM
> - Intel NUC mini PC
> - Beelink, MinisForum, or similar mini PC
> - Old laptop (just leave it plugged in)
>
> If you want something small and power-efficient, a **Raspberry Pi 4 or 5** also works — see the [Raspberry Pi guide](raspberry-pi.md).

---

## Step 1 — Install Ubuntu on the server

Your home server needs to run Ubuntu Linux. If it's already running Ubuntu 22.04 or newer, skip to Step 2.

**How to install Ubuntu:**

1. Download Ubuntu 22.04 LTS from [ubuntu.com/download/server](https://ubuntu.com/download/server)
2. Flash it to a USB drive using [Rufus](https://rufus.ie) (Windows) or [Etcher](https://etcher.balena.io) (Mac/Linux)
3. Plug the USB into your server, boot from it, and follow the installer
   - Choose **Ubuntu Server** (not Desktop — it uses less resources)
   - When asked about SSH, check **Install OpenSSH server**
   - Let it erase the disk and install

After installation, the server will reboot and show a login prompt.

---

## Step 2 — Find your server's local IP address

On the server, log in and run:

```bash
ip addr show
```

Look for a line like `inet 192.168.1.42/24` — the number before `/24` is your server's local IP address. Write it down.

Or, log into your router's admin page (usually at `http://192.168.1.1` or `http://192.168.0.1`) and look for "Connected devices" or "DHCP clients" — you should see your server listed there.

---

## Step 3 — Give your server a fixed IP address (recommended)

By default, your router assigns a random IP each time the server reboots, which is annoying. Fix this by reserving an IP in your router:

1. Log into your router admin page
2. Find **DHCP Reservations**, **Static DHCP**, or **Address Reservation**
3. Find your server in the list and assign it a permanent IP (e.g., `192.168.1.100`)

From now on, your server will always have the same local IP.

---

## Step 4 — SSH into your server from your main computer

From your main computer (Mac, Windows, or Linux):

**Mac/Linux terminal:**
```bash
ssh YOUR_USERNAME@192.168.1.100
```

Replace `YOUR_USERNAME` with the username you created during Ubuntu setup.

**Windows:** See the [Windows guide](windows.md) for SSH setup.

Once connected, switch to root:
```bash
sudo -i
```

---

## Step 5 — Run the setup

```bash
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

Follow the prompts. The script installs and configures everything automatically.

When asked about Tailscale, **say yes** — Tailscale is the easiest way to access your home server remotely.

---

## Step 6 — Access your agent

**From your home network (local access):**

The Control UI is at `http://192.168.1.100:18789/` — but it's bound to `127.0.0.1` by default, so you need to tunnel from your main computer:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@192.168.1.100
```

Then open `http://127.0.0.1:18789/` in your browser.

**From outside your home (remote access) — the easy way:**

Tailscale creates a secure tunnel to your home server from anywhere without needing to open any ports on your router. After authenticating Tailscale:

```bash
tailscale up
tailscale serve https / http://127.0.0.1:18789
```

You'll get a URL like `https://my-home-server.tail1234.ts.net/` that works from your phone, laptop, or anywhere.

---

## Optional: Keep the server running when the lid is closed (laptop)

If you're using a laptop as your server, stop it from sleeping when you close the lid:

```bash
sudo nano /etc/systemd/logind.conf
```

Find the line `#HandleLidSwitch=suspend` and change it to:
```
HandleLidSwitch=ignore
```

Save and restart: `sudo systemctl restart systemd-logind`

---

## Common problems

**Can't SSH from another computer on the same network:**
Make sure the Ubuntu firewall allows SSH: `sudo ufw allow ssh`

**Server is slow or runs out of memory:**
OpenClaw needs 4 GB RAM. Close other applications on the server or add more RAM.

**Power cuts cause data loss:**
Plug your server into a UPS (Uninterruptible Power Supply) if you have one. The automated backups help recover from unexpected shutdowns.

---

## What's next

- [Connect a messaging channel](https://docs.openclaw.ai/channels)
- [Enable the sandbox](../../README.md#after-the-script-finishes)
- [Automatic backups and updates](../../README.md#backup-and-restore)
