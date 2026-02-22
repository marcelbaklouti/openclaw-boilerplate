#!/usr/bin/env bash
set -euo pipefail
umask 077

OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/openclaw"
OPENCLAW_DATA_DIR="${OPENCLAW_HOME}/.openclaw"
OPENCLAW_REPO_DIR="${OPENCLAW_HOME}/openclaw"
OPENCLAW_IMAGE_TAG="openclaw:latest"
BACKUP_DIR="${OPENCLAW_HOME}/backups"

DOCKER_INSTALL_SHA256=""
TAILSCALE_INSTALL_SHA256=""

print_step() {
  echo ""
  echo "==> $1"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
  fi
}

detect_package_manager() {
  if command -v apt-get &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  else
    echo "unsupported"
  fi
}

install_base_packages() {
  print_step "Updating system and installing base packages"
  local pkg_manager
  pkg_manager="$(detect_package_manager)"

  case "${pkg_manager}" in
    apt)
      apt-get update -qq
      apt-get upgrade -y -qq
      apt-get install -y -qq \
        ufw \
        fail2ban \
        unattended-upgrades \
        curl \
        ca-certificates \
        git \
        openssl \
        logrotate
      dpkg-reconfigure -plow unattended-upgrades
      ;;
    dnf | yum)
      "${pkg_manager}" upgrade -y -q
      "${pkg_manager}" install -y -q \
        firewalld \
        fail2ban \
        curl \
        ca-certificates \
        git \
        openssl \
        logrotate
      systemctl enable --now firewalld
      ;;
    *)
      echo "Unsupported package manager. Install curl, git, openssl, a firewall, fail2ban, and logrotate manually." >&2
      exit 1
      ;;
  esac
}

configure_firewall() {
  print_step "Configuring firewall"

  if command -v ufw &>/dev/null; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw --force enable
  elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --set-default-zone=drop
    firewall-cmd --permanent --zone=drop --add-service=ssh
    firewall-cmd --reload
  else
    echo "No supported firewall found (ufw or firewalld). Configure your firewall manually." >&2
  fi
}

create_openclaw_user() {
  print_step "Creating dedicated openclaw user"
  if id "${OPENCLAW_USER}" &>/dev/null; then
    echo "User '${OPENCLAW_USER}' already exists, skipping."
    return
  fi
  useradd -r -m -d "${OPENCLAW_HOME}" -s /bin/bash "${OPENCLAW_USER}"
  echo "Set a password for the openclaw user:"
  passwd "${OPENCLAW_USER}"
}

validate_ssh_public_key() {
  local candidate_key="$1"

  if [[ "$(printf '%s' "${candidate_key}" | wc -l)" -gt 0 ]]; then
    return 1
  fi

  local key_type
  key_type="$(printf '%s' "${candidate_key}" | awk '{print $1}')"
  case "${key_type}" in
    ssh-rsa | ssh-ed25519 | ecdsa-sha2-nistp256 | ecdsa-sha2-nistp384 | ecdsa-sha2-nistp521 | sk-ssh-ed25519@openssh.com | sk-ecdsa-sha2-nistp256@openssh.com)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

setup_ssh_key_for_user() {
  print_step "Setting up SSH key for openclaw user"
  local ssh_dir="${OPENCLAW_HOME}/.ssh"
  local authorized_keys_file="${ssh_dir}/authorized_keys"

  mkdir -p "${ssh_dir}"
  chmod 700 "${ssh_dir}"

  if [[ -n "${OPENCLAW_SSH_PUBLIC_KEY:-}" ]]; then
    if ! validate_ssh_public_key "${OPENCLAW_SSH_PUBLIC_KEY}"; then
      echo "OPENCLAW_SSH_PUBLIC_KEY does not look like a valid SSH public key. Aborting." >&2
      exit 1
    fi
    printf '%s\n' "${OPENCLAW_SSH_PUBLIC_KEY}" > "${authorized_keys_file}"
  elif [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
    echo "Found root's authorized_keys - copying to openclaw user."
    cp /root/.ssh/authorized_keys "${authorized_keys_file}"
  else
    echo "Paste your SSH public key and press Enter, then Ctrl+D:"
    local pasted_key
    pasted_key="$(head -n 1)"
    if ! validate_ssh_public_key "${pasted_key}"; then
      echo "Input does not look like a valid SSH public key. Aborting." >&2
      exit 1
    fi
    printf '%s\n' "${pasted_key}" > "${authorized_keys_file}"
  fi

  chmod 600 "${authorized_keys_file}"
  chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${ssh_dir}"
}

harden_sshd() {
  print_step "Hardening SSH configuration"
  local sshd_config="/etc/ssh/sshd_config"

  if [[ -d /etc/ssh/sshd_config.d ]]; then
    local sshd_drop_in="/etc/ssh/sshd_config.d/99-openclaw-hardening.conf"
    cat > "${sshd_drop_in}" <<EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitUserEnvironment no
MaxAuthTries 3
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2
StrictModes yes
AllowUsers ${OPENCLAW_USER}
AuthorizedKeysFile .ssh/authorized_keys
Banner none
EOF
    chmod 600 "${sshd_drop_in}"
  else
    local hardening_lines=(
      "PermitRootLogin no"
      "PasswordAuthentication no"
      "KbdInteractiveAuthentication no"
      "ChallengeResponseAuthentication no"
      "PermitEmptyPasswords no"
      "X11Forwarding no"
      "AllowTcpForwarding no"
      "AllowAgentForwarding no"
      "PermitUserEnvironment no"
      "MaxAuthTries 3"
      "LoginGraceTime 20"
      "ClientAliveInterval 300"
      "ClientAliveCountMax 2"
      "StrictModes yes"
      "AllowUsers ${OPENCLAW_USER}"
      "AuthorizedKeysFile .ssh/authorized_keys"
      "Banner none"
    )
    for directive in "${hardening_lines[@]}"; do
      local key
      key="$(echo "${directive}" | awk '{print $1}')"
      if grep -qE "^#?${key}" "${sshd_config}"; then
        sed -i "s|^#\?${key}.*|${directive}|" "${sshd_config}"
      else
        echo "${directive}" >> "${sshd_config}"
      fi
    done
  fi

  systemctl restart sshd 2>/dev/null || systemctl restart ssh
}

configure_fail2ban() {
  print_step "Enabling fail2ban"
  systemctl enable fail2ban
  systemctl start fail2ban
}

fetch_live_checksum() {
  local url="$1"
  local tmp_file
  tmp_file="$(mktemp)"
  trap 'rm -f "${tmp_file}"' RETURN
  curl -fsSL "${url}" -o "${tmp_file}"
  sha256sum "${tmp_file}" | awk '{print $1}'
}

fetch_and_pin_checksums() {
  print_step "Fetching and pinning install script checksums"

  echo "Downloading Docker install script to compute checksum..."
  DOCKER_INSTALL_SHA256="$(fetch_live_checksum "https://get.docker.com")"
  echo "Docker SHA256: ${DOCKER_INSTALL_SHA256}"

  echo "Downloading Tailscale install script to compute checksum..."
  TAILSCALE_INSTALL_SHA256="$(fetch_live_checksum "https://tailscale.com/install.sh")"
  echo "Tailscale SHA256: ${TAILSCALE_INSTALL_SHA256}"

  echo "Checksums pinned. Each script will be re-downloaded and verified before execution."
  echo "A mismatch means the upstream script changed between our two fetches - a red flag."
}

download_and_verify() {
  local url="$1"
  local expected_sha256="$2"
  local output_file="$3"

  curl -fsSL "${url}" -o "${output_file}"

  local actual_sha256
  actual_sha256="$(sha256sum "${output_file}" | awk '{print $1}')"

  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    echo "Checksum mismatch for ${url}" >&2
    echo "  Expected: ${expected_sha256}" >&2
    echo "  Actual:   ${actual_sha256}" >&2
    echo "The script changed between checksum fetch and install download." >&2
    echo "This may indicate a supply chain issue. Aborting." >&2
    rm -f "${output_file}"
    exit 1
  fi

  echo "Checksum verified: $(basename "${output_file}")"
}

install_tailscale() {
  print_step "Installing Tailscale"
  if command -v tailscale &>/dev/null; then
    echo "Tailscale already installed, skipping."
    return
  fi

  local tmp_script
  tmp_script="$(mktemp /tmp/tailscale-install.XXXXXX.sh)"
  trap 'rm -f "${tmp_script}"' RETURN
  download_and_verify "https://tailscale.com/install.sh" "${TAILSCALE_INSTALL_SHA256}" "${tmp_script}"
  chmod 700 "${tmp_script}"
  bash "${tmp_script}"

  echo ""
  echo "Run 'tailscale up' to authenticate. After that connect via your Tailscale IP."
}

install_docker() {
  print_step "Installing Docker"
  if command -v docker &>/dev/null; then
    echo "Docker already installed, skipping."
  else
    local tmp_script
    tmp_script="$(mktemp /tmp/docker-install.XXXXXX.sh)"
    trap 'rm -f "${tmp_script}"' RETURN
    download_and_verify "https://get.docker.com" "${DOCKER_INSTALL_SHA256}" "${tmp_script}"
    chmod 700 "${tmp_script}"
    bash "${tmp_script}"
  fi
  usermod -aG docker "${OPENCLAW_USER}"
}

clone_openclaw_repo() {
  print_step "Cloning OpenClaw repository"
  if [[ -d "${OPENCLAW_REPO_DIR}" ]]; then
    echo "Repository already exists at ${OPENCLAW_REPO_DIR}, skipping clone."
    return
  fi
  sudo -u "${OPENCLAW_USER}" git clone https://github.com/openclaw/openclaw.git "${OPENCLAW_REPO_DIR}"
}

get_openclaw_uid() {
  id -u "${OPENCLAW_USER}"
}

get_openclaw_gid() {
  id -g "${OPENCLAW_USER}"
}

create_data_directories() {
  print_step "Creating persistent data directories"
  local openclaw_uid
  openclaw_uid="$(get_openclaw_uid)"
  local openclaw_gid
  openclaw_gid="$(get_openclaw_gid)"

  mkdir -p "${OPENCLAW_DATA_DIR}/workspace"
  chown -R "${openclaw_uid}:${openclaw_gid}" "${OPENCLAW_DATA_DIR}"

  mkdir -p "${BACKUP_DIR}"
  chown root:root "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"
}

generate_secret() {
  openssl rand -hex 32
}

create_env_file() {
  print_step "Generating .env file"
  local env_file="${OPENCLAW_REPO_DIR}/.env"

  if [[ -f "${env_file}" ]]; then
    echo ".env already exists, skipping generation."
    return
  fi

  local gateway_token
  gateway_token="$(generate_secret)"
  local keyring_password
  keyring_password="$(generate_secret)"

  install -o "${OPENCLAW_USER}" -g "${OPENCLAW_USER}" -m 600 /dev/null "${env_file}"

  cat > "${env_file}" <<EOF
OPENCLAW_IMAGE=${OPENCLAW_IMAGE_TAG}
OPENCLAW_GATEWAY_TOKEN=${gateway_token}
OPENCLAW_GATEWAY_BIND=loopback
OPENCLAW_GATEWAY_PORT=18789

OPENCLAW_CONFIG_DIR=${OPENCLAW_DATA_DIR}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_DATA_DIR}/workspace

GOG_KEYRING_PASSWORD=${keyring_password}
XDG_CONFIG_HOME=/home/node/.openclaw
EOF

  chmod 600 "${env_file}"
  chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${env_file}"
  echo ".env written to ${env_file} with auto-generated secrets."
}

create_docker_compose_file() {
  print_step "Writing docker-compose.yml"
  local compose_file="${OPENCLAW_REPO_DIR}/docker-compose.yml"

  if [[ -f "${compose_file}" ]]; then
    echo "docker-compose.yml already exists, skipping."
    return
  fi

  cat > "${compose_file}" <<'EOF'
services:
  openclaw-gateway:
    image: ${OPENCLAW_IMAGE}
    build: .
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - TERM=xterm-256color
      - OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND}
      - OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
      - XDG_CONFIG_HOME=${XDG_CONFIG_HOME}
      - PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    ports:
      - "127.0.0.1:${OPENCLAW_GATEWAY_PORT}:18789"
    read_only: true
    tmpfs:
      - /tmp:size=128m,noexec,nosuid,nodev
      - /home/node/.npm:size=64m,nosuid,nodev
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    mem_limit: 2g
    memswap_limit: 2g
    pids_limit: 256
    cpus: 2.0
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD-SHELL", "node -e \"require('http').get('http://127.0.0.1:18789/', r => process.exit(r.statusCode < 500 ? 0 : 1)).on('error', () => process.exit(1))\""]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind", "${OPENCLAW_GATEWAY_BIND}",
        "--port", "${OPENCLAW_GATEWAY_PORT}"
      ]
EOF

  chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${compose_file}"
}

sanitize_for_json() {
  local input="$1"
  printf '%s' "${input}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

create_openclaw_config() {
  print_step "Writing openclaw.json"
  local config_file="${OPENCLAW_DATA_DIR}/openclaw.json"

  if [[ -f "${config_file}" ]]; then
    echo "openclaw.json already exists, skipping."
    return
  fi

  echo ""
  echo "Enter your Telegram bot token (leave blank to configure later):"
  read -r -s telegram_bot_token

  echo "Enter your Telegram user ID (leave blank to configure later):"
  read -r telegram_user_id

  local telegram_enabled="false"
  local safe_bot_token="REPLACE_WITH_BOT_TOKEN"
  local safe_user_id="REPLACE_WITH_USER_ID"

  if [[ -n "${telegram_bot_token}" ]]; then
    telegram_enabled="true"
    safe_bot_token="$(sanitize_for_json "${telegram_bot_token}")"
    safe_bot_token="${safe_bot_token:1:-1}"
  fi

  if [[ -n "${telegram_user_id}" ]]; then
    safe_user_id="$(sanitize_for_json "tg:${telegram_user_id}")"
    safe_user_id="${safe_user_id:1:-1}"
  fi

  install -o "${OPENCLAW_USER}" -g "${OPENCLAW_USER}" -m 600 /dev/null "${config_file}"

  cat > "${config_file}" <<EOF
{
  "gateway": {
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "allowTailscale": false,
      "rateLimit": {
        "maxAttempts": 10,
        "windowMs": 60000,
        "lockoutMs": 300000,
        "exemptLoopback": true
      }
    },
    "controlUi": {
      "allowInsecureAuth": false
    },
    "tailscale": {
      "mode": "serve"
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-opus-4-6"
      },
      "sandbox": {
        "mode": "all",
        "scope": "agent",
        "workspaceAccess": "rw"
      }
    }
  },
  "channels": {
    "telegram": {
      "enabled": ${telegram_enabled},
      "botToken": "${safe_bot_token}",
      "dmPolicy": "allowlist",
      "allowFrom": ["${safe_user_id}"]
    }
  },
  "session": {
    "dmScope": "per-channel-peer"
  },
  "logging": {
    "redactSensitive": "tools"
  },
  "discovery": {
    "mdns": {
      "mode": "minimal"
    }
  }
}
EOF

  chmod 600 "${config_file}"
  chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${config_file}"

  unset telegram_bot_token
}

setup_log_rotation() {
  cat > /etc/logrotate.d/openclaw-update <<'EOF'
/var/log/openclaw-update.log {
    weekly
    rotate 12
    compress
    missingok
    notifempty
    create 640 root root
}
EOF
}

install_update_script() {
  local update_script_dest="/usr/local/bin/openclaw-update.sh"
  local bundled_update_script
  bundled_update_script="$(dirname "$(realpath "$0")")/openclaw-update.sh"

  if [[ -f "${bundled_update_script}" ]]; then
    cp "${bundled_update_script}" "${update_script_dest}"
  else
    cat > "${update_script_dest}" <<'UPDATEEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

OPENCLAW_REPO_DIR="/home/openclaw/openclaw"
OPENCLAW_DATA_DIR="/home/openclaw/.openclaw"
BACKUP_DIR="/home/openclaw/backups"
LOG_FILE="/var/log/openclaw-update.log"
LOCK_FILE="/var/lock/openclaw-update.lock"
BACKUP_RETENTION_DAYS=30

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "openclaw-update.sh must be run as root." >&2
    exit 1
  fi
}

acquire_lock() {
  exec 9>"${LOCK_FILE}"
  if ! flock -n 9; then
    log "Another update is already running. Exiting."
    exit 1
  fi
}

create_backup() {
  if [[ ! -d "${BACKUP_DIR}" ]]; then
    mkdir -p "${BACKUP_DIR}"
    chown root:root "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
  fi
  local backup_filename
  backup_filename="${BACKUP_DIR}/openclaw-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "${backup_filename}" "${OPENCLAW_DATA_DIR}"
  chmod 600 "${backup_filename}"
  chown root:root "${backup_filename}"
  log "Backup created: ${backup_filename}"
}

prune_old_backups() {
  find "${BACKUP_DIR}" -maxdepth 1 -name "openclaw-backup-*.tar.gz" -mtime "+${BACKUP_RETENTION_DAYS}" -delete
  log "Backups older than ${BACKUP_RETENTION_DAYS} days pruned"
}

rebuild_and_restart_container() {
  cd "${OPENCLAW_REPO_DIR}"
  git pull origin main >> "${LOG_FILE}" 2>&1
  docker compose build >> "${LOG_FILE}" 2>&1
  docker compose up -d openclaw-gateway >> "${LOG_FILE}" 2>&1
  log "Docker image rebuilt and container restarted"
}

main() {
  require_root
  acquire_lock
  log "Starting OpenClaw update"
  create_backup
  prune_old_backups
  rebuild_and_restart_container
  log "Update complete"
}

main
UPDATEEOF
  fi

  chmod 700 "${update_script_dest}"
  chown root:root "${update_script_dest}"
}

setup_auto_update_cron() {
  print_step "Setting up weekly auto-update cron job"
  install_update_script
  setup_log_rotation

  local cron_file="/etc/cron.d/openclaw-update"
  echo "0 3 * * 0 root /usr/local/bin/openclaw-update.sh" > "${cron_file}"
  chmod 644 "${cron_file}"
  chown root:root "${cron_file}"
  echo "Cron job written to ${cron_file} (runs Sundays at 03:00)"
}

build_and_start_container() {
  print_step "Building Docker image and starting container"
  cd "${OPENCLAW_REPO_DIR}"
  sudo -u "${OPENCLAW_USER}" docker compose build
  sudo -u "${OPENCLAW_USER}" docker compose up -d openclaw-gateway
  echo ""
  echo "Container started. Tailing logs for 10 seconds..."
  sudo -u "${OPENCLAW_USER}" docker compose logs --tail=20 openclaw-gateway &
  local log_pid=$!
  sleep 10
  kill "${log_pid}" 2>/dev/null || true
}

verify_gateway_binding() {
  print_step "Verifying gateway is bound only to loopback"
  echo "Expected: 127.0.0.1:18789 (NOT 0.0.0.0)"
  if ss -tlnp | grep 18789 | grep -q "127.0.0.1"; then
    echo "OK: Gateway is correctly bound to 127.0.0.1 only."
  elif ss -tlnp | grep -q 18789; then
    echo "WARNING: Gateway is listening but not on 127.0.0.1 - check docker-compose.yml ports binding." >&2
  else
    echo "Gateway not yet listening - check container logs." >&2
  fi
}

run_security_audit() {
  print_step "Running OpenClaw security audit"

  echo "Waiting for gateway to be ready (up to 30s)..."
  local elapsed=0
  until sudo -u "${OPENCLAW_USER}" docker compose -f "${OPENCLAW_REPO_DIR}/docker-compose.yml" exec -T openclaw-gateway openclaw --version &>/dev/null; do
    if [[ "${elapsed}" -ge 30 ]]; then
      echo "Gateway did not become ready within 30s - skipping automated audit."
      echo "Run manually once it's up:"
      echo "  docker exec -it openclaw-gateway openclaw doctor"
      echo "  docker exec -it openclaw-gateway openclaw security audit --deep"
      return
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo ""
  echo "--- openclaw doctor ---"
  sudo -u "${OPENCLAW_USER}" docker compose -f "${OPENCLAW_REPO_DIR}/docker-compose.yml" \
    exec -T openclaw-gateway openclaw doctor || true

  echo ""
  echo "--- openclaw security audit --deep ---"
  local audit_exit_code=0
  sudo -u "${OPENCLAW_USER}" docker compose -f "${OPENCLAW_REPO_DIR}/docker-compose.yml" \
    exec -T openclaw-gateway openclaw security audit --deep || audit_exit_code=$?

  if [[ "${audit_exit_code}" -ne 0 ]]; then
    echo ""
    echo "WARNING: Security audit returned issues (exit code ${audit_exit_code})." >&2
    echo "         Review the output above and resolve before going live." >&2
  else
    echo ""
    echo "Security audit passed with 0 critical issues."
  fi
}

print_next_steps() {
  echo ""
  echo "================================================================"
  echo " OpenClaw setup complete"
  echo "================================================================"
  echo ""
  echo "IMPORTANT: SSH is now restricted to the 'openclaw' user only."
  echo "Verify you can connect before closing this session:"
  echo "  ssh openclaw@<your-server-ip>"
  echo ""
  echo "Next steps:"
  echo ""
  echo "1. Authenticate Tailscale:"
  echo "   tailscale up"
  echo ""
  echo "2. Expose Control UI via Tailscale (recommended):"
  echo "   tailscale serve https / http://127.0.0.1:18789"
  echo ""
  echo "   Or via SSH tunnel from your local machine:"
  echo "   ssh -N -L 18789:127.0.0.1:18789 openclaw@<your-server-ip>"
  echo "   Then open: http://127.0.0.1:18789/"
  echo ""
  echo "3. Fill in placeholders if you skipped Telegram setup:"
  echo "   nano ${OPENCLAW_DATA_DIR}/openclaw.json"
  echo ""
  echo "Auto-updates: every Sunday at 03:00 via /etc/cron.d/openclaw-update"
  echo "Update logs:  /var/log/openclaw-update.log (rotated weekly, kept 12 weeks)"
  echo "Backups:      ${BACKUP_DIR} (root-only, 30-day retention)"
  echo "================================================================"
}

main() {
  require_root
  fetch_and_pin_checksums
  install_base_packages
  create_openclaw_user
  setup_ssh_key_for_user
  harden_sshd
  configure_firewall
  configure_fail2ban
  install_tailscale
  install_docker
  clone_openclaw_repo
  create_data_directories
  create_env_file
  create_docker_compose_file
  create_openclaw_config
  setup_auto_update_cron
  build_and_start_container
  verify_gateway_binding
  run_security_audit
  print_next_steps
}

main
