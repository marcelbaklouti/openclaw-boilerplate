# QuickStart: Deploy on Windows (via WSL2)

**Difficulty:** Intermediate (a few Windows-specific steps first)
**Time:** 20–35 minutes
**Works on:** Windows 10 (version 2004 or later) and Windows 11

OpenClaw's setup script runs on Linux. On Windows, you use **WSL2** (Windows Subsystem for Linux) — a real Linux system built into Windows. It runs in the background alongside Windows and feels like any other app.

> **Alternative:** If you'd rather not run Linux inside Windows, you can rent a cheap VPS for ~$5/month and use the [VPS guide](vps.md) instead. That's often simpler.

---

## What you need before you start

- Windows 10 version 2004 or later, or Windows 11
- At least **8 GB RAM** in your PC (4 GB for WSL2 + 4 GB for Windows)
- An internet connection

---

## Step 1 — Enable WSL2

**Option A — Windows Store (easiest):**
Open the Microsoft Store, search for **"Ubuntu"**, and install **Ubuntu 22.04 LTS**. It installs WSL2 automatically.

**Option B — PowerShell:**
Open PowerShell as Administrator (right-click the Start button → **Windows PowerShell (Admin)**) and run:

```powershell
wsl --install -d Ubuntu-22.04
```

Restart your computer when prompted.

---

## Step 2 — Set up Ubuntu

After restarting, Ubuntu will open and ask you to:
1. Create a **username** (something simple, no spaces, e.g., `ubuntu`)
2. Create a **password** (you'll need this for `sudo` commands)

Once that's done, you have a working Linux terminal inside Windows.

---

## Step 3 — Update Ubuntu

In the Ubuntu terminal, run:

```bash
sudo apt update && sudo apt upgrade -y
```

---

## Step 4 — Run the OpenClaw setup

Now run the standard setup — it's exactly the same as on a Linux server:

```bash
sudo -i
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

Follow the prompts. The script configures everything automatically.

---

## Step 5 — Access the Control UI

Once setup is complete, the Control UI runs on `http://127.0.0.1:18789/`.

**Good news:** On WSL2, `127.0.0.1` in the Linux environment is accessible directly from Windows. Open your Windows browser and go to:

```
http://127.0.0.1:18789/
```

It should just work.

> If it doesn't, you may need to forward the port. In the Ubuntu terminal:
> ```bash
> # Find your WSL2 IP
> ip addr show eth0 | grep 'inet '
> ```
> Then in Windows PowerShell (as Administrator):
> ```powershell
> netsh interface portproxy add v4tov4 listenport=18789 listenaddress=127.0.0.1 connectport=18789 connectaddress=WSL2_IP_HERE
> ```

---

## Step 6 — Keep OpenClaw running

By default, WSL2 shuts down when you close the terminal. To keep OpenClaw running in the background:

**Keep the terminal open** in the background (minimize it instead of closing).

**Or set up WSL2 to stay running:**
Open Windows Task Scheduler and create a task that runs `wsl -d Ubuntu-22.04` at login with no window. This keeps the Linux environment alive.

**Or use Windows Terminal** (download from the Microsoft Store) — it's much nicer than the default terminal and you can keep WSL running as a tab.

---

## SSH into a remote server from Windows

If instead of running locally you want to SSH into a remote server (VPS, cloud, home server), WSL2 gives you the standard `ssh` command:

```bash
ssh root@YOUR_SERVER_IP
ssh -i ~/my-key.pem ubuntu@YOUR_SERVER_IP
```

You can also use WSL2 to run the `git clone` + `bash setup.sh` commands remotely over SSH.

---

## Optional: Windows Terminal + SSH config

Windows Terminal (free from the Microsoft Store) makes working with WSL2 much nicer. You get tabs, profiles, and nice fonts.

To avoid typing the full SSH command every time, create an SSH config file:

```bash
mkdir -p ~/.ssh
nano ~/.ssh/config
```

Add entries like:
```
Host my-server
    HostName 203.0.113.42
    User openclaw
    IdentityFile ~/.ssh/id_ed25519
```

Then connect with just: `ssh my-server`

---

## Common problems

**"WSL2 kernel update required":**
Download and install the WSL2 kernel update from [Microsoft's WSL documentation](https://learn.microsoft.com/en-us/windows/wsl/install-manual#step-4---download-the-linux-kernel-update-package).

**"Error: 0x80370102" when starting Ubuntu:**
Virtualization isn't enabled in your BIOS. Restart your PC, enter BIOS (usually Del or F2 at startup), and enable **Intel VT-x** or **AMD-V**.

**Control UI not accessible at 127.0.0.1:18789:**
Make sure OpenClaw is actually running: `systemctl status openclaw-gateway` in the Ubuntu terminal. If it says "inactive", start it: `systemctl start openclaw-gateway`.

**WSL2 uses too much RAM:**
WSL2 can use a lot of RAM. Create a file `C:\Users\YOUR_NAME\.wslconfig` (in Notepad) with:
```
[wsl2]
memory=4GB
processors=2
```
Then restart WSL: `wsl --shutdown` in PowerShell.

---

## What's next

- [Connect a messaging channel](https://docs.openclaw.ai/channels)
- [Enable the sandbox](../../README.md#after-the-script-finishes)
- [Automatic backups and updates](../../README.md#backup-and-restore)
