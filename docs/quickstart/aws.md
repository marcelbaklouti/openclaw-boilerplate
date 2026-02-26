# QuickStart: Deploy on AWS EC2

**Difficulty:** Beginner-friendly (a few extra AWS-specific steps)
**Time:** About 20–30 minutes
**Cost:** The `t3.medium` (2 vCPU, 4 GB RAM) costs about $30/month. Check [AWS Free Tier](https://aws.amazon.com/free/) — new accounts may qualify for 750 hours/month of `t2.micro` free for 12 months (but that's only 1 GB RAM, which is below the minimum — use a paid instance for reliable operation).

AWS (Amazon Web Services) is the world's largest cloud provider. It takes a few more steps than a simple VPS, but it's very reliable and has a global presence.

---

## What you need before you start

- An AWS account (free to create at aws.amazon.com)
- A credit/debit card (AWS requires one even for free-tier usage)
- A computer with a terminal

---

## Step 1 — Sign in to the AWS Console

Go to [aws.amazon.com](https://aws.amazon.com) and click **Sign In to the Console**.

---

## Step 2 — Launch an EC2 instance

1. In the search bar at the top, type **EC2** and click it
2. Click the orange **Launch instance** button
3. Fill in the form:

   - **Name:** `openclaw-server` (or anything you like)
   - **Application and OS Images:** Click **Ubuntu**, then choose **Ubuntu Server 22.04 LTS** (should be selected by default)
   - **Instance type:** Choose `t3.medium` (2 vCPU, 4 GB RAM) — or `t3.large` for more headroom
   - **Key pair (login):** Click **Create new key pair**
     - Name it something like `openclaw-key`
     - Key pair type: **RSA**
     - Private key file format: **.pem** (Mac/Linux) or **.ppk** (Windows with PuTTY)
     - Click **Create key pair** — it will download a file like `openclaw-key.pem` — **save this file somewhere safe, you can't download it again**
   - **Network settings:** Leave the defaults (a security group will be created allowing SSH)
   - **Storage:** Change to at least **20 GiB** (the default 8 GiB is too small)

4. Click the orange **Launch instance** button on the right

---

## Step 3 — Allow SSH in the security group (if needed)

If you didn't add an SSH rule during instance creation:

1. Click on your new instance in the EC2 dashboard
2. Scroll down to the **Security** tab
3. Click the security group link
4. Click **Edit inbound rules** → **Add rule**
5. Type: **SSH**, Source: **My IP** (this is safer than "Anywhere")
6. Click **Save rules**

---

## Step 4 — Find your server's IP address

1. Go back to **EC2 → Instances**
2. Click your instance
3. Copy the **Public IPv4 address** (looks like `3.14.159.26`)

---

## Step 5 — Connect to your server

**On Mac/Linux:**

First, fix the permissions on your downloaded key file (required by SSH):

```bash
chmod 400 ~/Downloads/openclaw-key.pem
```

Then connect:

```bash
ssh -i ~/Downloads/openclaw-key.pem ubuntu@YOUR_SERVER_IP
```

> Note: AWS Ubuntu instances use the username `ubuntu`, not `root`.

**On Windows:**
See the [Windows guide](windows.md) for how to connect using WSL or PuTTY.

---

## Step 6 — Become root and run the setup

Once connected, switch to root:

```bash
sudo -i
```

Then run the setup:

```bash
git clone https://github.com/marcelbaklouti/openclaw-boilerplate.git
cd openclaw-boilerplate
bash setup.sh
```

Follow the prompts — the script handles everything automatically.

---

## Step 7 — Access your agent

**Option A — SSH tunnel (quick):**

From a new terminal window on your computer:

```bash
ssh -N -L 18789:127.0.0.1:18789 -i ~/Downloads/openclaw-key.pem ubuntu@YOUR_SERVER_IP
```

Leave that window open, then open `http://127.0.0.1:18789/` in your browser.

**Option B — Tailscale (recommended for regular use):**

If you authenticated Tailscale during setup, the Control UI is available at your Tailscale URL from anywhere.

---

## Saving money: stop vs terminate

- **Stop** = pause the server. You're not charged for compute time, but you still pay for the disk (~$0.10/GB/month). Use this to pause without losing your data.
- **Terminate** = permanently delete the server. You stop paying entirely.

To stop: EC2 → Instances → select your instance → **Instance state → Stop instance**

---

## Common problems

**"Warning: Unprotected private key file":**
Run `chmod 400 ~/Downloads/openclaw-key.pem` to fix permissions.

**"Connection timed out":**
Check that your security group allows inbound SSH (port 22) from your IP. Your IP may have changed — update the security group.

**"Host key verification failed":**
If you've re-created the instance, run `ssh-keygen -R YOUR_SERVER_IP` to clear the cached key.

---

## What's next

- [Connect a messaging channel](https://docs.openclaw.ai/channels)
- [Enable the sandbox](../../README.md#after-the-script-finishes)
- [Automatic backups and updates](../../README.md#backup-and-restore)
