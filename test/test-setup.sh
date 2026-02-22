#!/usr/bin/env bash
# Smoke-test for setup.sh inside a Docker container.
#
# Runs setup.sh in non-interactive mode and validates that each major step
# completed correctly. Skips steps that require real infrastructure (Tailscale
# auth, Docker-in-Docker build, live network).
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed

set -euo pipefail

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); }

section() { echo ""; echo "=== $1 ==="; }

# ---------------------------------------------------------------------------
# Phase 1: Run setup.sh in non-interactive mode
# ---------------------------------------------------------------------------
section "Running setup.sh (non-interactive)"

# Provide SSH key via env var to skip interactive prompt
export OPENCLAW_SSH_PUBLIC_KEY
OPENCLAW_SSH_PUBLIC_KEY="$(cat /root/.ssh/authorized_keys)"

# setup.sh calls several external installers (Docker, Tailscale) and tries to
# build/start a container.  We stub out the steps that need real infra and let
# everything else run for real.

# Create a wrapper that intercepts commands we can't run in the test container
mkdir -p /usr/local/lib/openclaw-test
cat > /usr/local/lib/openclaw-test/stub-docker <<'STUB'
#!/usr/bin/env bash
# Stub: pretend docker is installed
if [[ "${1:-}" == "compose" ]]; then
  echo "[test-stub] docker compose $* (skipped)"
  exit 0
fi
echo "[test-stub] docker $* (skipped)"
exit 0
STUB
chmod +x /usr/local/lib/openclaw-test/stub-docker

cat > /usr/local/lib/openclaw-test/stub-tailscale <<'STUB'
#!/usr/bin/env bash
echo "[test-stub] tailscale $* (skipped)"
exit 0
STUB
chmod +x /usr/local/lib/openclaw-test/stub-tailscale

# Pre-install stubs so setup.sh skips download steps
cp /usr/local/lib/openclaw-test/stub-docker /usr/local/bin/docker
cp /usr/local/lib/openclaw-test/stub-tailscale /usr/local/bin/tailscale

# Pre-create the openclaw repo directory so clone is skipped
# (we can't clone from github in a hermetic test)
useradd -r -m -d /home/openclaw -s /bin/bash openclaw 2>/dev/null || true
mkdir -p /home/openclaw/openclaw
chown openclaw:openclaw /home/openclaw/openclaw

# Stub out passwd to avoid interactive prompt
cat > /usr/local/bin/passwd <<'STUB'
#!/usr/bin/env bash
echo "[test-stub] passwd $* (skipped)"
exit 0
STUB
chmod +x /usr/local/bin/passwd

# Stub out git clone (already pre-created)
GIT_REAL="$(command -v git)"

# Stub ss for gateway verification
cat > /usr/local/bin/ss <<'STUB'
#!/usr/bin/env bash
# Pretend gateway is bound to loopback
echo "LISTEN 0 4096 127.0.0.1:18789 0.0.0.0:*"
STUB
chmod +x /usr/local/bin/ss

# Run setup.sh - feed default answers for interactive prompts:
#   Line 1: AI provider choice (1 = Anthropic, the default)
#   Line 2: AI API key (blank = configure later)
#   Line 3: Telegram bot token (blank = configure later)
#   Line 4: Telegram user ID (blank = configure later)
echo "Running setup.sh..."
SETUP_OUTPUT=$(printf '1\n\n\n\n' | bash /opt/openclaw-boilerplate/setup.sh 2>&1) || true
SETUP_EXIT=$?

echo ""
echo "--- setup.sh output (last 30 lines) ---"
echo "${SETUP_OUTPUT}" | tail -30
echo "--- end output ---"

# ---------------------------------------------------------------------------
# Phase 2: Validate results
# ---------------------------------------------------------------------------

section "Validating user and directory setup"

if id openclaw &>/dev/null; then
  pass "openclaw user exists"
else
  fail "openclaw user does not exist"
fi

if [[ -d /home/openclaw/.openclaw ]]; then
  pass "data directory /home/openclaw/.openclaw exists"
else
  fail "data directory /home/openclaw/.openclaw missing"
fi

if [[ -d /home/openclaw/.openclaw/workspace ]]; then
  pass "workspace directory exists"
else
  fail "workspace directory missing"
fi

if [[ -d /home/openclaw/backups ]]; then
  pass "backup directory exists"
else
  fail "backup directory missing"
fi

BACKUP_PERMS=$(stat -c '%a' /home/openclaw/backups)
if [[ "${BACKUP_PERMS}" == "700" ]]; then
  pass "backup directory permissions are 700"
else
  fail "backup directory permissions are ${BACKUP_PERMS}, expected 700"
fi

section "Validating SSH configuration"

if [[ -f /home/openclaw/.ssh/authorized_keys ]]; then
  pass "authorized_keys file exists for openclaw user"
else
  fail "authorized_keys file missing for openclaw user"
fi

SSH_KEY_PERMS=$(stat -c '%a' /home/openclaw/.ssh/authorized_keys)
if [[ "${SSH_KEY_PERMS}" == "600" ]]; then
  pass "authorized_keys permissions are 600"
else
  fail "authorized_keys permissions are ${SSH_KEY_PERMS}, expected 600"
fi

SSH_DIR_PERMS=$(stat -c '%a' /home/openclaw/.ssh)
if [[ "${SSH_DIR_PERMS}" == "700" ]]; then
  pass ".ssh directory permissions are 700"
else
  fail ".ssh directory permissions are ${SSH_DIR_PERMS}, expected 700"
fi

# Check sshd hardening
SSHD_HARDENED=false
if [[ -f /etc/ssh/sshd_config.d/99-openclaw-hardening.conf ]]; then
  SSHD_HARDENED=true
  pass "sshd drop-in config created"

  if grep -q "PermitRootLogin no" /etc/ssh/sshd_config.d/99-openclaw-hardening.conf; then
    pass "PermitRootLogin disabled"
  else
    fail "PermitRootLogin not disabled in drop-in"
  fi

  if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config.d/99-openclaw-hardening.conf; then
    pass "PasswordAuthentication disabled"
  else
    fail "PasswordAuthentication not disabled in drop-in"
  fi

  if grep -q "AllowUsers openclaw" /etc/ssh/sshd_config.d/99-openclaw-hardening.conf; then
    pass "AllowUsers restricted to openclaw"
  else
    fail "AllowUsers not restricted"
  fi
else
  # Fallback: check main sshd_config
  if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
    pass "PermitRootLogin disabled (main config)"
  else
    fail "PermitRootLogin not disabled"
  fi
fi

section "Validating firewall"

if command -v ufw &>/dev/null; then
  UFW_STATUS=$(ufw status 2>/dev/null || echo "inactive")
  if echo "${UFW_STATUS}" | grep -qi "active"; then
    pass "ufw is active"
  else
    # UFW may not work in containers without iptables kernel modules
    skip "ufw not active (expected in Docker containers without NET_ADMIN)"
  fi
else
  skip "ufw not installed (non-Debian system or test limitation)"
fi

section "Validating generated config files"

ENV_FILE="/home/openclaw/openclaw/.env"
if [[ -f "${ENV_FILE}" ]]; then
  pass ".env file created"

  ENV_PERMS=$(stat -c '%a' "${ENV_FILE}")
  if [[ "${ENV_PERMS}" == "600" ]]; then
    pass ".env permissions are 600"
  else
    fail ".env permissions are ${ENV_PERMS}, expected 600"
  fi

  if grep -q "OPENCLAW_GATEWAY_TOKEN=" "${ENV_FILE}"; then
    TOKEN_VAL=$(grep "OPENCLAW_GATEWAY_TOKEN=" "${ENV_FILE}" | cut -d= -f2)
    TOKEN_LEN=${#TOKEN_VAL}
    if [[ "${TOKEN_LEN}" -eq 64 ]]; then
      pass "gateway token is 64 hex chars"
    else
      fail "gateway token length is ${TOKEN_LEN}, expected 64"
    fi
  else
    fail "OPENCLAW_GATEWAY_TOKEN not found in .env"
  fi

  if grep -q "GOG_KEYRING_PASSWORD=" "${ENV_FILE}"; then
    pass "keyring password present in .env"
  else
    fail "GOG_KEYRING_PASSWORD not found in .env"
  fi

  if grep -q "OPENCLAW_GATEWAY_BIND=loopback" "${ENV_FILE}"; then
    pass "gateway bind set to loopback"
  else
    fail "gateway bind not set to loopback"
  fi
else
  fail ".env file not created"
fi

API_ENV_FILE="/home/openclaw/.openclaw/.env"
if [[ -f "${API_ENV_FILE}" ]]; then
  pass "API key env file created at ~/.openclaw/.env"

  API_ENV_PERMS=$(stat -c '%a' "${API_ENV_FILE}")
  if [[ "${API_ENV_PERMS}" == "600" ]]; then
    pass "API key env file permissions are 600"
  else
    fail "API key env file permissions are ${API_ENV_PERMS}, expected 600"
  fi

  if grep -q "ANTHROPIC_API_KEY=" "${API_ENV_FILE}"; then
    pass "default provider (Anthropic) API key placeholder present"
  else
    fail "ANTHROPIC_API_KEY not found in API env file"
  fi
else
  fail "API key env file not created"
fi

CONFIG_FILE="/home/openclaw/.openclaw/openclaw.json"
if [[ -f "${CONFIG_FILE}" ]]; then
  pass "openclaw.json created"

  CONFIG_PERMS=$(stat -c '%a' "${CONFIG_FILE}")
  if [[ "${CONFIG_PERMS}" == "600" ]]; then
    pass "openclaw.json permissions are 600"
  else
    fail "openclaw.json permissions are ${CONFIG_PERMS}, expected 600"
  fi

  # Validate JSON is well-formed
  if python3 -c "import json; json.load(open('${CONFIG_FILE}'))" 2>/dev/null; then
    pass "openclaw.json is valid JSON"
  else
    fail "openclaw.json is not valid JSON"
  fi

  if grep -q '"dmPolicy": "allowlist"' "${CONFIG_FILE}"; then
    pass "DM policy set to allowlist"
  else
    fail "DM policy not set to allowlist"
  fi

  if grep -q '"mode": "all"' "${CONFIG_FILE}"; then
    pass "sandbox mode set to all"
  else
    fail "sandbox mode not set to all"
  fi
else
  fail "openclaw.json not created"
fi

COMPOSE_FILE="/home/openclaw/openclaw/docker-compose.yml"
if [[ -f "${COMPOSE_FILE}" ]]; then
  pass "docker-compose.yml created"

  if grep -q "127.0.0.1" "${COMPOSE_FILE}"; then
    pass "docker-compose binds to 127.0.0.1"
  else
    fail "docker-compose does not bind to 127.0.0.1"
  fi

  if grep -q "read_only: true" "${COMPOSE_FILE}"; then
    pass "container filesystem is read-only"
  else
    fail "container filesystem not read-only"
  fi

  if grep -q "no-new-privileges" "${COMPOSE_FILE}"; then
    pass "no-new-privileges set"
  else
    fail "no-new-privileges not set"
  fi

  if grep -q "cap_drop" "${COMPOSE_FILE}"; then
    pass "capabilities dropped"
  else
    fail "capabilities not dropped"
  fi
else
  fail "docker-compose.yml not created"
fi

section "Validating auto-update setup"

if [[ -f /usr/local/bin/openclaw-update.sh ]]; then
  pass "update script installed to /usr/local/bin"

  UPDATE_PERMS=$(stat -c '%a' /usr/local/bin/openclaw-update.sh)
  if [[ "${UPDATE_PERMS}" == "700" ]]; then
    pass "update script permissions are 700"
  else
    fail "update script permissions are ${UPDATE_PERMS}, expected 700"
  fi
else
  fail "update script not installed"
fi

if [[ -f /etc/cron.d/openclaw-update ]]; then
  pass "cron job created"

  if grep -q "0 3 \* \* 0" /etc/cron.d/openclaw-update; then
    pass "cron schedule is Sunday 03:00"
  else
    fail "cron schedule incorrect"
  fi
else
  fail "cron job not created"
fi

if [[ -f /etc/logrotate.d/openclaw-update ]]; then
  pass "logrotate config created"
else
  fail "logrotate config not created"
fi

section "Validating fail2ban"

if command -v fail2ban-client &>/dev/null; then
  pass "fail2ban installed"
else
  fail "fail2ban not installed"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Results"
echo ""
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo "  Skipped: ${SKIP}"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: FAIL (${FAIL} checks failed)"
  exit 1
else
  echo "RESULT: PASS (all ${PASS} checks passed, ${SKIP} skipped)"
  exit 0
fi
