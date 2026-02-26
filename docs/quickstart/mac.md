# QuickStart: Deploy on a Mac

**Difficulty:** Beginner-friendly
**Time:** 20–40 minutes
**Works on:** Any Mac (Apple Silicon M1/M2/M3/M4 or Intel)

OpenClaw's setup script runs on Linux. To run it on a Mac, you create a small Linux virtual machine (VM) — a Linux computer that lives inside your Mac. It's easier than it sounds and uses very little of your Mac's resources.

**Which tool should I use?**

| Tool | Best for | Cost |
|---|---|---|
| **Lume** | Apple Silicon Macs (M1/M2/M3/M4) — fastest, native performance | Free |
| **UTM** | Any Mac (Intel or Apple Silicon) — more features, GUI | Free |
| **OrbStack** | Any Mac — polished UI, Linux machines + Docker | Free for personal use |

Pick the section below that matches your Mac.

---

## Option A — Lume (Apple Silicon only — M1, M2, M3, M4)

Lume uses Apple's built-in virtualization to run Linux VMs at near-native speed. It's lightweight, headless (no GUI window), and takes about 5 minutes to set up.

> **Check your chip:** Click the Apple logo → About This Mac. If it says "Apple M1" (or M2/M3/M4), use this option. If it says "Intel", skip to Option B.

### Install Lume

Open **Terminal** (press `Cmd + Space`, type Terminal, press Enter).

Install Homebrew if you don't have it:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install Lume:
```bash
brew tap trycua/lume
brew install lume
```

### Create an Ubuntu VM

```bash
lume run ubuntu-24:latest --name openclaw-vm --cpus 2 --memory 4096
```

This downloads an Ubuntu 24.04 image (about 1 GB) and starts it. The first run takes a few minutes. When it's ready, you'll see a login prompt.

### Find the VM's IP address

```bash
lume list
```

Look for your VM's IP address in the output (something like `192.168.64.5`).

### SSH into the VM

```bash
ssh ubuntu@VM_IP_ADDRESS
```

Default password for Lume Ubuntu images: `ubuntu`

Switch to root:
```bash
sudo -i
```

### Run the OpenClaw setup

```bash
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

Follow the prompts. Done!

### Access the Control UI

From a new Terminal window on your Mac:

```bash
ssh -N -L 18789:127.0.0.1:18789 ubuntu@VM_IP_ADDRESS
```

Leave that open, then visit `http://127.0.0.1:18789/` in your browser.

### Keep the VM running in the background

```bash
# Stop the VM when you don't need it
lume stop openclaw-vm

# Start it again later
lume start openclaw-vm

# Check if it's running
lume list
```

---

## Option B — UTM (Any Mac — Intel or Apple Silicon)

UTM is a graphical virtualization app for Mac. It's more beginner-friendly if you prefer a visual interface.

### Install UTM

1. Go to [mac.getutm.app](https://mac.getutm.app) and download UTM
2. Open the downloaded `.dmg` and drag UTM to your Applications folder

### Create an Ubuntu VM

1. Open UTM
2. Click **Create a New Virtual Machine**
3. Choose **Virtualize** (if on Apple Silicon) or **Emulate** (if on Intel — slower but works)
4. Choose **Linux**
5. Boot image: Click **Browse** and select an Ubuntu 22.04 Server ISO you downloaded from [ubuntu.com/download/server](https://ubuntu.com/download/server)
6. Memory: Set to at least **4096 MB** (4 GB)
7. CPU cores: **2**
8. Storage: **20 GB** minimum
9. Name it `openclaw` and click **Save**

### Install Ubuntu in the VM

1. Click the play button to start the VM
2. Follow the Ubuntu Server installer:
   - Choose language → English
   - Use default storage layout
   - Set your name and a username (e.g., `ubuntu`) and a password
   - When asked "Install OpenSSH Server" — **check this box**
   - Let it finish and reboot

### Find the VM's IP

Once Ubuntu boots and you log in, run:
```bash
ip addr show
```

Look for `inet 192.168.X.X` — that's the VM's IP address.

### SSH into the VM and run setup

From your Mac Terminal:
```bash
ssh ubuntu@VM_IP_ADDRESS
sudo -i
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

### Access the Control UI

```bash
ssh -N -L 18789:127.0.0.1:18789 ubuntu@VM_IP_ADDRESS
```

Then open `http://127.0.0.1:18789/` in your browser.

---

## Option C — OrbStack (Any Mac, polished experience)

[OrbStack](https://orbstack.dev) is a fast, lightweight alternative to Docker Desktop that also supports full Linux machines. It's the smoothest experience on Mac.

### Install OrbStack

Download from [orbstack.dev](https://orbstack.dev) and install it like a regular Mac app.

### Create a Linux machine

Open OrbStack → click **Machines** → **New Machine**:
- Distribution: **Ubuntu 22.04**
- Name: `openclaw`
- CPU: 2, Memory: 4 GB

Click **Create**.

### SSH into the machine

OrbStack sets up SSH automatically:
```bash
ssh ubuntu@openclaw@orb
```

Switch to root and run setup:
```bash
sudo -i
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

### Access the Control UI

```bash
ssh -N -L 18789:127.0.0.1:18789 ubuntu@openclaw@orb
```

Then open `http://127.0.0.1:18789/` in your browser.

---

## Tips for all Mac options

**Free up resources when not using OpenClaw:**
Stop the VM to reclaim RAM and CPU. Start it again when you need your agent.

**Auto-start on login (Lume):**
```bash
lume start openclaw-vm
```

Add this to your shell profile (`~/.zshrc`) to start automatically.

**Check your Mac's memory:**
OpenClaw's VM needs 4 GB. If your Mac only has 8 GB, allocate 4 GB to the VM and keep 4 GB for macOS.

---

## What's next

- [Connect a messaging channel](https://docs.openclaw.ai/channels)
- [Enable the sandbox](../../README.md#after-the-script-finishes)
- [Automatic backups and updates](../../README.md#backup-and-restore)
