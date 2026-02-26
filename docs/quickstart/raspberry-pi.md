# QuickStart: Deploy on a Raspberry Pi

**Difficulty:** Intermediate
**Time:** 30–45 minutes
**Cost:** ~$60–80 one-time hardware cost (Pi 4 or Pi 5) + electricity (~$2–5/month)

A Raspberry Pi is a tiny, low-power Linux computer that fits in your hand. It runs 24/7 and uses less electricity than a phone charger. It's a great option if you want a dedicated home server without the noise or cost of a full PC.

---

## What you need before you start

- **Raspberry Pi 4 (4 GB or 8 GB RAM)** or **Raspberry Pi 5 (4 GB or 8 GB RAM)**
  > Do NOT use Pi 3 or earlier — they don't have enough RAM. Pi 4 with 2 GB RAM is also tight; 4 GB is recommended.
- A **microSD card** (32 GB or larger, Class 10 or faster — Samsung or SanDisk recommended)
- A **USB-C power supply** (official Raspberry Pi one is best)
- An **ethernet cable** (optional but strongly recommended — more reliable than Wi-Fi)
- A computer to set up the SD card (Windows, Mac, or Linux)

---

## Step 1 — Flash Ubuntu Server onto the SD card

The easiest way is to use **Raspberry Pi Imager** (free tool from the Raspberry Pi Foundation).

1. Download it from [raspberrypi.com/software](https://www.raspberrypi.com/software/)
2. Insert your microSD card into your computer
3. Open Raspberry Pi Imager
4. Click **Choose Device** → select your Pi model
5. Click **Choose OS** → **Other general-purpose OS** → **Ubuntu** → **Ubuntu Server 22.04 LTS (64-bit)**
6. Click **Choose Storage** → select your SD card
7. Click **Next** → Click **Edit Settings** (the gear icon)

In the settings popup, configure:
- **Hostname:** `openclaw` (optional, but useful)
- **Enable SSH:** Check this box → **Use password authentication**
- **Set username and password:** Choose a username (e.g., `ubuntu`) and a strong password
- **Configure Wi-Fi** (optional if using ethernet)

8. Click **Save** → **Yes** → wait for it to flash (takes a few minutes)

---

## Step 2 — Boot the Pi

1. Insert the SD card into the Raspberry Pi
2. Plug in the ethernet cable (if using)
3. Plug in the power supply

Wait about 60 seconds for it to boot fully.

---

## Step 3 — Find the Pi's IP address

**Option A — Check your router:**
Log into your router's admin page (usually at `http://192.168.1.1`) and look for "Connected devices" or "DHCP clients". You should see `openclaw` (or `raspberrypi`) in the list with its IP address.

**Option B — Use the hostname (if mDNS works):**
```bash
ping openclaw.local
```

This works on most home networks.

---

## Step 4 — SSH into the Pi

From your computer's terminal:

```bash
ssh ubuntu@192.168.1.YOUR_PI_IP
```

Or if using hostname:
```bash
ssh ubuntu@openclaw.local
```

Enter the password you set during imaging.

Switch to root:
```bash
sudo -i
```

---

## Step 5 — Update the system (important for Pi)

Before running the setup, update the OS — this ensures you have the latest security patches and drivers:

```bash
apt update && apt upgrade -y
```

This may take a few minutes. Reboot if prompted:
```bash
reboot
```

SSH back in after rebooting.

---

## Step 6 — Run the OpenClaw setup

```bash
sudo -i
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

The script runs automatically and asks you a few questions. Follow the prompts.

> **Expect it to be slower than a full PC** — the Pi's SD card and CPU are not as fast. The full setup may take 15–25 minutes on a Pi 4.

---

## Step 7 — Access the Control UI

**SSH tunnel (from your computer):**

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@192.168.1.YOUR_PI_IP
```

Leave that open and visit `http://127.0.0.1:18789/` in your browser.

**Tailscale (access from anywhere):**

If you authenticated Tailscale during setup, you can access the Control UI from anywhere:
```bash
tailscale up
tailscale serve https / http://127.0.0.1:18789
```

---

## Tips for Raspberry Pi

**Use a quality SD card:**
Cheap SD cards wear out faster and can corrupt your data. Use a Samsung Endurance Pro, SanDisk Endurance, or similar card designed for continuous write operations.

**Even better — use a USB SSD:**
A USB 3.0 SSD is much faster and longer-lasting than an SD card. You can boot the Pi from USB by changing the boot order in `raspi-config`.

**Keep the Pi cool:**
The Pi 4/5 can get hot under load. A case with a heatsink or small fan keeps it running reliably.

**Set a static IP:**
Log into your router and assign a fixed IP address to the Pi's MAC address. This way its IP never changes.

**Keep it running 24/7:**
Unlike a laptop or desktop, the Pi is designed to run continuously. Just plug it in somewhere with good airflow and leave it.

---

## Common problems

**SD card gets corrupted after a power cut:**
This can happen with cheap SD cards or if the Pi loses power suddenly. Use a quality card, and consider a UPS (Uninterruptible Power Supply) or at minimum always shut down cleanly: `sudo shutdown -h now`

**Setup is very slow:**
This is normal on Pi 4 with an SD card. Be patient. If it's taking more than 30 minutes, check that you're using a fast SD card (Class 10, A2 rated).

**"Cannot allocate memory" errors:**
If you have a 2 GB Pi, OpenClaw may be tight on RAM. Upgrade to a 4 GB or 8 GB model, or add a swap file:
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
```

---

## What's next

- [Connect a messaging channel](https://docs.openclaw.ai/channels)
- [Enable the sandbox](../../README.md#after-the-script-finishes)
- [Automatic backups and updates](../../README.md#backup-and-restore)
