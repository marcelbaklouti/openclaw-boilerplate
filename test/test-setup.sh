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

cat > /usr/local/lib/openclaw-test/stub-systemctl <<'STUB'
#!/usr/bin/env bash
echo "[test-stub] systemctl $* (skipped)"
exit 0
STUB
chmod +x /usr/local/lib/openclaw-test/stub-systemctl

# Pre-install stubs so setup.sh skips download steps
cp /usr/local/lib/openclaw-test/stub-docker /usr/local/bin/docker
cp /usr/local/lib/openclaw-test/stub-tailscale /usr/local/bin/tailscale
cp /usr/local/lib/openclaw-test/stub-systemctl /usr/local/bin/systemctl

cat > /usr/local/lib/openclaw-test/stub-openclaw <<'STUB'
#!/usr/bin/env bash
echo "[test-stub] openclaw $* (skipped)"
exit 0
STUB
chmod +x /usr/local/lib/openclaw-test/stub-openclaw
cp /usr/local/lib/openclaw-test/stub-openclaw /usr/local/bin/openclaw

cat > /usr/local/lib/openclaw-test/stub-npm <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "10.0.0"
  exit 0
fi
echo "[test-stub] npm $* (skipped)"
exit 0
STUB
chmod +x /usr/local/lib/openclaw-test/stub-npm
cp /usr/local/lib/openclaw-test/stub-npm /usr/local/bin/npm

cat > /usr/local/lib/openclaw-test/stub-node <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "v22.0.0"
  exit 0
fi
echo "[test-stub] node $* (skipped)"
exit 0
STUB
chmod +x /usr/local/lib/openclaw-test/stub-node
cp /usr/local/lib/openclaw-test/stub-node /usr/local/bin/node

useradd -r -m -d /home/openclaw -s /bin/bash openclaw 2>/dev/null || true

# Create docker group since the real Docker install isn't running
groupadd -f docker

# Stub out passwd to avoid interactive prompt
cat > /usr/local/bin/passwd <<'STUB'
#!/usr/bin/env bash
echo "[test-stub] passwd $* (skipped)"
exit 0
STUB
chmod +x /usr/local/bin/passwd

# Stub ss for gateway verification
cat > /usr/local/bin/ss <<'STUB'
#!/usr/bin/env bash
# Pretend gateway is bound to loopback
echo "LISTEN 0 4096 127.0.0.1:18789 0.0.0.0:*"
STUB
chmod +x /usr/local/bin/ss

# Set env vars for non-interactive channel and Tailscale setup
export OPENCLAW_CHANNEL=telegram
export OPENCLAW_SKIP_TAILSCALE_AUTH=1
# sshd -t is structurally unreliable in the smoke-test container (no dbus,
# cgroup restrictions, restricted init).  The file-content checks below are
# sufficient for CI; the daemon test runs on real server provisioning.
export OPENCLAW_SKIP_SSHD_TEST=1

# Run setup.sh - feed default answers for interactive prompts:
#   Line 1: AI provider choice (1 = Anthropic, the default)
#   Line 2: AI API key (blank = configure later)
#   Line 3: Telegram bot token (blank = configure later)
#   Line 4: Telegram user ID (blank = configure later)
echo "Running setup.sh..."
SETUP_OUTPUT=$(printf '1\n\n\n\n' | bash /opt/openclaw-boilerplate/setup.sh 2>&1) || true

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

# In the container smoke-test the sshd -t daemon check is intentionally skipped.
# Confirm that setup.sh logged the skip message (proves the right branch ran).
if echo "${SETUP_OUTPUT}" | grep -q "sshd -t validation skipped"; then
  pass "sshd -t skipped cleanly in container (expected)"
else
  fail "Expected sshd -t skip message not found in setup output"
fi


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
if [[ -f /etc/ssh/sshd_config.d/99-openclaw-hardening.conf ]]; then
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

  if grep -q "HostbasedAuthentication no" /etc/ssh/sshd_config.d/99-openclaw-hardening.conf; then
    pass "HostbasedAuthentication disabled"
  else
    fail "HostbasedAuthentication not disabled in drop-in"
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

CONFIG_FILE="/home/openclaw/.openclaw/openclaw.json"

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
gw = cfg.get('gateway', {})
assert gw.get('mode') == 'local', 'gateway.mode not local'
" 2>/dev/null; then
  pass "gateway.mode set to local"
else
  fail "gateway.mode not set to local"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
gw = cfg.get('gateway', {})
assert gw.get('auth', {}).get('allowTailscale') == True, 'allowTailscale not true'
" 2>/dev/null; then
  pass "gateway.auth.allowTailscale set to true"
else
  fail "gateway.auth.allowTailscale not set to true"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
tools = cfg.get('tools', {})
assert tools.get('profile') == 'full', 'tools.profile not full'
assert tools.get('fs', {}).get('workspaceOnly') == True, 'fs.workspaceOnly not true'
assert tools.get('exec', {}).get('ask') == 'always', 'exec.ask not always'
assert tools.get('elevated', {}).get('enabled') == False, 'elevated.enabled not false'
" 2>/dev/null; then
  pass "tools security baseline configured (profile=full, workspaceOnly, exec.ask=always, no elevated)"
else
  fail "tools security baseline not configured"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
plugins = cfg.get('plugins', {})
assert plugins.get('security', {}).get('autoLoadWorkspace') == False, 'autoLoadWorkspace not false'
" 2>/dev/null; then
  pass "plugins.security.autoLoadWorkspace set to false"
else
  fail "plugins.security.autoLoadWorkspace not set to false"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
agents = cfg.get('agents', {})
assert agents.get('defaults', {}).get('thinking') == 'adaptive', 'thinking not adaptive'
" 2>/dev/null; then
  pass "agents.defaults.thinking set to adaptive"
else
  fail "agents.defaults.thinking not set to adaptive"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
assert cfg.get('browser', {}).get('enabled') == False, 'browser not disabled'
" 2>/dev/null; then
  pass "browser disabled by default"
else
  fail "browser not disabled by default"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
maint = cfg.get('session', {}).get('maintenance', {})
assert maint.get('mode') == 'enforce', 'maintenance mode not enforce'
assert maint.get('pruneAfter') == '30d', 'pruneAfter not 30d'
assert maint.get('maxEntries') == 500, 'maxEntries not 500'
" 2>/dev/null; then
  pass "session.maintenance configured (enforce, 30d prune, 500 max entries)"
else
  fail "session.maintenance not configured"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
cui = cfg.get('gateway', {}).get('controlUi', {})
assert cui.get('dangerouslyDisableDeviceAuth') == False, 'device auth not enforced'
" 2>/dev/null; then
  pass "gateway.controlUi.dangerouslyDisableDeviceAuth explicitly false"
else
  fail "gateway.controlUi.dangerouslyDisableDeviceAuth not set"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
reset = cfg.get('session', {}).get('reset', {})
assert reset.get('mode') == 'daily', 'session.reset.mode not daily'
assert reset.get('atHour') == 4, 'session.reset.atHour not 4'
assert reset.get('idleMinutes') == 120, 'session.reset.idleMinutes not 120'
" 2>/dev/null; then
  pass "session.reset configured for daily resets"
else
  fail "session.reset not configured"
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

  if grep -q '"dmPolicy": "pairing"' "${CONFIG_FILE}"; then
    pass "DM policy set to pairing"
  else
    fail "DM policy not set to pairing"
  fi

  if grep -q '"mode": "off"' "${CONFIG_FILE}"; then
    pass "sandbox mode set to off"
  else
    fail "sandbox mode not set to off"
  fi

  if grep -q '"telegram"' "${CONFIG_FILE}"; then
    pass "telegram channel present in config"
  else
    fail "telegram channel not found in config"
  fi

  if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
ch = cfg.get('channels', {})
tg = ch.get('telegram', {})
assert 'botToken' in tg, 'missing botToken'
assert 'allowFrom' in tg, 'missing allowFrom'
assert tg.get('dmPolicy') == 'pairing', 'wrong dmPolicy'
assert tg.get('groups', {}).get('*', {}).get('requireMention') == True, 'missing groups mention gating'
assert tg.get('persistBindings') == True, 'missing persistBindings'
" 2>/dev/null; then
    pass "telegram channel structure is valid (including persistBindings)"
  else
    fail "telegram channel structure is invalid"
  fi
else
  fail "openclaw.json not created"
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

section "Validating channel env var pre-configuration"

if echo "${SETUP_OUTPUT}" | grep -q "Using channel from OPENCLAW_CHANNEL env var"; then
  pass "OPENCLAW_CHANNEL env var was recognized"
else
  fail "OPENCLAW_CHANNEL env var not recognized in setup output"
fi

if echo "${SETUP_OUTPUT}" | grep -q "OPENCLAW_SKIP_TAILSCALE_AUTH is set"; then
  pass "OPENCLAW_SKIP_TAILSCALE_AUTH env var was recognized"
else
  fail "OPENCLAW_SKIP_TAILSCALE_AUTH env var not recognized in setup output"
fi

if python3 -c "
import json
cfg = json.load(open('${CONFIG_FILE}'))
ch = cfg.get('channels', {})
assert 'telegram' in ch, 'telegram channel missing'
assert 'discord' not in ch, 'unexpected discord channel'
assert 'whatsapp' not in ch, 'unexpected whatsapp channel'
assert 'slack' not in ch, 'unexpected slack channel'
" 2>/dev/null; then
  pass "only the selected channel (telegram) was written to config"
else
  fail "unexpected channels in config"
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
