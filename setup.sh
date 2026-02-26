#!/usr/bin/env bash
set -euo pipefail
umask 077

OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/openclaw"
OPENCLAW_DATA_DIR="${OPENCLAW_HOME}/.openclaw"
BACKUP_DIR="${OPENCLAW_HOME}/backups"

CHANNEL=""
NEEDS_ONBOARD_WIZARD=false

DOCKER_INSTALL_SHA256=""
TAILSCALE_INSTALL_SHA256=""
OPENCLAW_INSTALL_SHA256=""
NODESOURCE_INSTALL_URL=""
NODESOURCE_INSTALL_SHA256=""

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
        dnf-automatic \
        curl \
        ca-certificates \
        git \
        openssl \
        logrotate
      systemctl enable --now firewalld
      # Enable automatic security updates (RHEL/Fedora equivalent of unattended-upgrades)
      sed -i 's/^upgrade_type.*/upgrade_type = security/' /etc/dnf/automatic.conf
      systemctl enable --now dnf-automatic-install.timer
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
    # Add SSH to drop zone (permanent + runtime) BEFORE switching default,
    # so the active SSH session is not interrupted during zone change.
    firewall-cmd --permanent --zone=drop --add-service=ssh
    firewall-cmd --zone=drop --add-service=ssh
    firewall-cmd --set-default-zone=drop
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

  # sshd -t requires host keys to exist. Generate any missing ones now so the
  # config test works even in freshly provisioned containers or images.
  if ! ls /etc/ssh/ssh_host_*_key &>/dev/null 2>&1; then
    ssh-keygen -A &>/dev/null
  fi

  if [[ -d /etc/ssh/sshd_config.d ]]; then
    local sshd_drop_in="/etc/ssh/sshd_config.d/99-openclaw-hardening.conf"
    cat > "${sshd_drop_in}" <<EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
HostbasedAuthentication no
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
    if ! sshd -t 2>/dev/null; then
      echo "ERROR: sshd configuration test failed after writing drop-in. Removing drop-in and aborting." >&2
      rm -f "${sshd_drop_in}"
      exit 1
    fi
  else
    # Backup the original config so we can roll back if validation fails
    local sshd_backup="${sshd_config}.pre-openclaw.bak"
    cp "${sshd_config}" "${sshd_backup}"
    chmod 600 "${sshd_backup}"

    local hardening_lines=(
      "PermitRootLogin no"
      "PasswordAuthentication no"
      "KbdInteractiveAuthentication no"
      "ChallengeResponseAuthentication no"
      "HostbasedAuthentication no"
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

    if ! sshd -t 2>/dev/null; then
      echo "ERROR: sshd configuration test failed after hardening. Restoring backup and aborting." >&2
      cp "${sshd_backup}" "${sshd_config}"
      exit 1
    fi
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

  if ! command -v docker &>/dev/null; then
    echo "Downloading Docker install script to compute checksum..."
    DOCKER_INSTALL_SHA256="$(fetch_live_checksum "https://get.docker.com")"
    echo "Docker SHA256: ${DOCKER_INSTALL_SHA256}"
  fi

  if ! command -v tailscale &>/dev/null; then
    echo "Downloading Tailscale install script to compute checksum..."
    TAILSCALE_INSTALL_SHA256="$(fetch_live_checksum "https://tailscale.com/install.sh")"
    echo "Tailscale SHA256: ${TAILSCALE_INSTALL_SHA256}"
  fi

  if ! command -v openclaw &>/dev/null; then
    echo "Downloading OpenClaw install script to compute checksum..."
    OPENCLAW_INSTALL_SHA256="$(fetch_live_checksum "https://openclaw.ai/install.sh")"
    echo "OpenClaw SHA256: ${OPENCLAW_INSTALL_SHA256}"
  fi

  local needs_node=false
  if ! command -v node &>/dev/null; then
    needs_node=true
  else
    local node_major
    node_major="$(node --version 2>/dev/null | tr -d 'v' | cut -d. -f1)"
    if [[ "${node_major}" -lt 22 ]]; then
      needs_node=true
    fi
  fi

  if [[ "${needs_node}" == "true" ]]; then
    local pkg_manager
    pkg_manager="$(detect_package_manager)"
    case "${pkg_manager}" in
      apt)   NODESOURCE_INSTALL_URL="https://deb.nodesource.com/setup_22.x" ;;
      dnf | yum) NODESOURCE_INSTALL_URL="https://rpm.nodesource.com/setup_22.x" ;;
      *) ;;
    esac
    if [[ -n "${NODESOURCE_INSTALL_URL}" ]]; then
      echo "Downloading NodeSource setup script to compute checksum..."
      NODESOURCE_INSTALL_SHA256="$(fetch_live_checksum "${NODESOURCE_INSTALL_URL}")"
      echo "NodeSource SHA256: ${NODESOURCE_INSTALL_SHA256}"
    fi
  fi

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
  systemctl enable --now docker
  usermod -aG docker "${OPENCLAW_USER}"
}

install_node() {
  print_step "Installing Node.js 22 LTS"
  if command -v node &>/dev/null; then
    local node_major
    node_major="$(node --version 2>/dev/null | tr -d 'v' | cut -d. -f1)"
    if [[ "${node_major}" -ge 22 ]]; then
      echo "Node.js $(node --version) already installed, skipping."
      return
    fi
    echo "Node.js $(node --version) found but 22+ required. Upgrading..."
  fi

  local pkg_manager
  pkg_manager="$(detect_package_manager)"

  case "${pkg_manager}" in
    apt | dnf | yum)
      if [[ -z "${NODESOURCE_INSTALL_URL}" ]] || [[ -z "${NODESOURCE_INSTALL_SHA256}" ]]; then
        echo "NodeSource checksum not available - run fetch_and_pin_checksums first." >&2
        exit 1
      fi
      local tmp_script
      tmp_script="$(mktemp /tmp/nodesource-setup.XXXXXX.sh)"
      trap 'rm -f "${tmp_script}"' RETURN
      download_and_verify "${NODESOURCE_INSTALL_URL}" "${NODESOURCE_INSTALL_SHA256}" "${tmp_script}"
      chmod 700 "${tmp_script}"
      bash "${tmp_script}"
      if [[ "${pkg_manager}" == "apt" ]]; then
        apt-get install -y -qq nodejs
      else
        "${pkg_manager}" install -y -q nodejs
      fi
      ;;
    *)
      echo "Install Node.js 22+ manually: https://nodejs.org/" >&2
      exit 1
      ;;
  esac

  echo "Node.js $(node --version) and npm $(npm --version) installed."
}

install_openclaw() {
  print_step "Installing OpenClaw via official installer"
  if command -v openclaw &>/dev/null; then
    echo "OpenClaw already installed, skipping."
    return
  fi

  local tmp_script
  tmp_script="$(mktemp /tmp/openclaw-install.XXXXXX.sh)"
  trap 'rm -f "${tmp_script}"' RETURN
  download_and_verify "https://openclaw.ai/install.sh" "${OPENCLAW_INSTALL_SHA256}" "${tmp_script}"
  chmod 700 "${tmp_script}"
  bash "${tmp_script}" -- --no-onboard
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

sanitize_for_json() {
  local input="$1"
  printf '%s' "${input}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

select_ai_provider() {
  print_step "Selecting AI model provider"
  echo ""
  echo "Choose an AI model provider for the agent:"
  echo ""
  echo "  1) Anthropic Claude (claude-opus-4-6)  — commercial API key required"
  echo "  2) MiniMax M2.5        — much cheaper (\$0.30/\$1.20 per 1M tokens), MIT license"
  echo "  3) GLM-5 (Zhipu AI)   — very affordable (\$0.30/\$2.55 per 1M tokens), MIT license"
  echo "  4) Custom              — any OpenAI-compatible API endpoint"
  echo ""
  echo "Note: Options 2 and 3 are open-weight models available via multiple API"
  echo "providers (or self-hosted). They score competitively on agentic benchmarks"
  echo "and cost a fraction of proprietary alternatives."
  echo ""

  local choice
  while true; do
    read -r -p "Enter choice [1-4] (default: 1): " choice
    choice="${choice:-1}"
    case "${choice}" in
      1)
        AI_PROVIDER="anthropic"
        AI_MODEL="anthropic/claude-opus-4-6"
        AI_API_KEY_ENV="ANTHROPIC_API_KEY"
        echo ""
        echo "Enter your Anthropic API key (leave blank to configure later):"
        read -r -s ai_api_key
        break
        ;;
      2)
        AI_PROVIDER="minimax"
        AI_MODEL="minimax/MiniMax-M2.5"
        AI_API_KEY_ENV="MINIMAX_API_KEY"
        echo ""
        echo "Enter your MiniMax API key (leave blank to configure later):"
        read -r -s ai_api_key
        break
        ;;
      3)
        AI_PROVIDER="zhipu"
        AI_MODEL="zhipu/glm-5"
        AI_API_KEY_ENV="ZHIPU_API_KEY"
        echo ""
        echo "Enter your Zhipu AI (GLM-5) API key (leave blank to configure later):"
        read -r -s ai_api_key
        break
        ;;
      4)
        AI_PROVIDER="custom"
        echo ""
        echo "Enter the model identifier (e.g. openai/gpt-4o, deepseek/deepseek-v3.2):"
        read -r AI_MODEL
        AI_API_KEY_ENV="OPENAI_API_KEY"
        echo ""
        echo "Enter the API base URL (leave blank for provider default):"
        read -r AI_API_BASE_URL
        echo ""
        echo "Enter your API key (leave blank to configure later):"
        read -r -s ai_api_key
        break
        ;;
      *)
        echo "Invalid choice. Enter 1, 2, 3, or 4."
        ;;
    esac
  done

  echo ""
  echo "Selected model: ${AI_MODEL}"
}

store_ai_api_key() {
  local env_file="${OPENCLAW_DATA_DIR}/.env"

  install -o "${OPENCLAW_USER}" -g "${OPENCLAW_USER}" -m 600 /dev/null "${env_file}"

  local env_content="${AI_API_KEY_ENV}=${ai_api_key:-REPLACE_WITH_API_KEY}"
  if [[ "${AI_PROVIDER}" == "custom" ]] && [[ -n "${AI_API_BASE_URL:-}" ]]; then
    env_content="${env_content}
OPENAI_API_BASE_URL=${AI_API_BASE_URL}"
  fi

  printf '%s\n' "${env_content}" > "${env_file}"
  chmod 600 "${env_file}"
  chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${env_file}"
  echo "API key written to ${env_file}"

  unset ai_api_key
}

select_channel() {
  print_step "Selecting messaging channel"

  if [[ -n "${OPENCLAW_CHANNEL:-}" ]]; then
    CHANNEL="${OPENCLAW_CHANNEL}"
    echo "Using channel from OPENCLAW_CHANNEL env var: ${CHANNEL}"
    case "${CHANNEL}" in
      telegram | discord) ;;
      whatsapp | slack) NEEDS_ONBOARD_WIZARD=true ;;
      none) ;;
      *)
        echo "Unsupported OPENCLAW_CHANNEL value: ${CHANNEL}. Use telegram, discord, whatsapp, slack, or none." >&2
        exit 1
        ;;
    esac
    return
  fi

  echo ""
  echo "Choose a messaging channel to connect to your agent:"
  echo ""
  echo "  1) Telegram  - Bot token + user ID (configure here)"
  echo "  2) Discord   - Bot token + user ID (configure here)"
  echo "  3) WhatsApp  - Requires OAuth (completed via onboard wizard)"
  echo "  4) Slack     - Requires OAuth (completed via onboard wizard)"
  echo "  5) None      - Configure a channel later"
  echo ""

  local choice
  while true; do
    read -r -p "Enter choice [1-5] (default: 1): " choice
    choice="${choice:-1}"
    case "${choice}" in
      1) CHANNEL="telegram"; break ;;
      2) CHANNEL="discord"; break ;;
      3) CHANNEL="whatsapp"; NEEDS_ONBOARD_WIZARD=true; break ;;
      4) CHANNEL="slack"; NEEDS_ONBOARD_WIZARD=true; break ;;
      5) CHANNEL="none"; break ;;
      *) echo "Invalid choice. Enter 1, 2, 3, 4, or 5." ;;
    esac
  done

  echo "Selected channel: ${CHANNEL}"
}

collect_channel_credentials() {
  telegram_bot_token=""
  telegram_user_id=""
  discord_bot_token=""
  discord_user_id=""

  case "${CHANNEL}" in
    telegram)
      if [[ -n "${OPENCLAW_TELEGRAM_BOT_TOKEN+set}" ]]; then
        telegram_bot_token="${OPENCLAW_TELEGRAM_BOT_TOKEN}"
      else
        echo ""
        echo "Enter your Telegram bot token (leave blank to configure later):"
        read -r -s telegram_bot_token
      fi

      if [[ -n "${OPENCLAW_TELEGRAM_USER_ID+set}" ]]; then
        telegram_user_id="${OPENCLAW_TELEGRAM_USER_ID}"
      else
        echo "Enter your Telegram user ID (leave blank to configure later):"
        read -r telegram_user_id
      fi
      ;;
    discord)
      if [[ -n "${OPENCLAW_DISCORD_BOT_TOKEN+set}" ]]; then
        discord_bot_token="${OPENCLAW_DISCORD_BOT_TOKEN}"
      else
        echo ""
        echo "Enter your Discord bot token (leave blank to configure later):"
        read -r -s discord_bot_token
      fi

      if [[ -n "${OPENCLAW_DISCORD_USER_ID+set}" ]]; then
        discord_user_id="${OPENCLAW_DISCORD_USER_ID}"
      else
        echo "Enter your Discord user ID (leave blank to configure later):"
        read -r discord_user_id
      fi
      ;;
    whatsapp | slack)
      echo ""
      echo "${CHANNEL} requires OAuth authentication."
      echo "The onboard wizard will run after the daemon starts."
      ;;
    none)
      echo "No channel selected. Configure one later in openclaw.json."
      ;;
  esac
}

build_channel_json() {
  local channel_json=""

  case "${CHANNEL}" in
    telegram)
      local tg_enabled="false"
      local safe_bot_token="REPLACE_WITH_BOT_TOKEN"
      local safe_user_id="REPLACE_WITH_USER_ID"

      if [[ -n "${telegram_bot_token}" ]]; then
        tg_enabled="true"
        safe_bot_token="$(sanitize_for_json "${telegram_bot_token}")"
        safe_bot_token="${safe_bot_token:1:-1}"
      fi

      if [[ -n "${telegram_user_id}" ]]; then
        safe_user_id="$(sanitize_for_json "tg:${telegram_user_id}")"
        safe_user_id="${safe_user_id:1:-1}"
      fi

      channel_json="$(cat <<CEOF
    "telegram": {
      "enabled": ${tg_enabled},
      "botToken": "${safe_bot_token}",
      "dmPolicy": "pairing",
      "allowFrom": ["${safe_user_id}"],
      "groups": { "*": { "requireMention": true } }
    }
CEOF
)"
      ;;
    discord)
      local dc_enabled="false"
      local safe_bot_token="REPLACE_WITH_BOT_TOKEN"
      local safe_user_id="REPLACE_WITH_USER_ID"

      if [[ -n "${discord_bot_token}" ]]; then
        dc_enabled="true"
        safe_bot_token="$(sanitize_for_json "${discord_bot_token}")"
        safe_bot_token="${safe_bot_token:1:-1}"
      fi

      if [[ -n "${discord_user_id}" ]]; then
        safe_user_id="$(sanitize_for_json "discord:${discord_user_id}")"
        safe_user_id="${safe_user_id:1:-1}"
      fi

      channel_json="$(cat <<CEOF
    "discord": {
      "enabled": ${dc_enabled},
      "token": "${safe_bot_token}",
      "dmPolicy": "pairing",
      "allowFrom": ["${safe_user_id}"],
      "groups": { "*": { "requireMention": true } }
    }
CEOF
)"
      ;;
    whatsapp)
      channel_json='    "whatsapp": {
      "enabled": false,
      "dmPolicy": "pairing",
      "groups": { "*": { "requireMention": true } }
    }'
      ;;
    slack)
      channel_json='    "slack": {
      "enabled": false,
      "dmPolicy": "pairing"
    }'
      ;;
    none)
      channel_json=""
      ;;
  esac

  printf '%s' "${channel_json}"
}

create_openclaw_config() {
  print_step "Writing openclaw.json"
  local config_file="${OPENCLAW_DATA_DIR}/openclaw.json"

  if [[ -f "${config_file}" ]]; then
    echo "openclaw.json already exists, skipping."
    return
  fi

  local channel_json
  channel_json="$(build_channel_json)"

  install -o "${OPENCLAW_USER}" -g "${OPENCLAW_USER}" -m 600 /dev/null "${config_file}"

  local channels_block
  if [[ -n "${channel_json}" ]]; then
    channels_block="$(cat <<CHEOF
  "channels": {
${channel_json}
  },
CHEOF
)"
  else
    channels_block='  "channels": {},'
  fi

  cat > "${config_file}" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "allowTailscale": true,
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
        "primary": "${AI_MODEL}"
      },
      "sandbox": {
        "mode": "off",
        "scope": "agent",
        "workspaceAccess": "rw"
      }
    }
  },
  "tools": {
    "fs": { "workspaceOnly": true },
    "elevated": { "enabled": false }
  },
${channels_block}
  "session": {
    "dmScope": "per-channel-peer",
    "reset": {
      "mode": "daily",
      "atHour": 4,
      "idleMinutes": 120
    }
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

  unset telegram_bot_token discord_bot_token
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

update_and_restart() {
  npm update -g openclaw@latest >> "${LOG_FILE}" 2>&1
  systemctl restart openclaw-gateway >> "${LOG_FILE}" 2>&1
  log "OpenClaw updated and gateway restarted"
}

main() {
  require_root
  acquire_lock
  log "Starting OpenClaw update"
  create_backup
  prune_old_backups
  update_and_restart
  log "Update complete"
}

main
UPDATEEOF
  fi

  chmod 700 "${update_script_dest}"
  chown root:root "${update_script_dest}"

  local restore_script_dest="/usr/local/bin/openclaw-restore.sh"
  local bundled_restore_script
  bundled_restore_script="$(dirname "$(realpath "$0")")/openclaw-restore.sh"

  if [[ -f "${bundled_restore_script}" ]]; then
    cp "${bundled_restore_script}" "${restore_script_dest}"
    chmod 700 "${restore_script_dest}"
    chown root:root "${restore_script_dest}"
  fi
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

  local npm_cron="/etc/cron.d/openclaw-npm-security"
  echo "0 2 * * * root npm update -g npm@latest >> /var/log/openclaw-update.log 2>&1" > "${npm_cron}"
  chmod 644 "${npm_cron}"
  chown root:root "${npm_cron}"
  echo "Daily npm update cron written to ${npm_cron} (runs daily at 02:00)"
}

start_openclaw_daemon() {
  print_step "Installing and starting OpenClaw daemon"
  sudo -u "${OPENCLAW_USER}" openclaw onboard --install-daemon --non-interactive || {
    echo "Daemon install via onboard failed. Starting manually..." >&2
    systemctl enable --now openclaw-gateway 2>/dev/null || true
  }
  echo ""
  echo "Daemon installed. Checking status..."
  systemctl status openclaw-gateway --no-pager 2>/dev/null || true
}

verify_gateway_binding() {
  print_step "Verifying gateway is bound only to loopback"
  echo "Expected: 127.0.0.1:18789 (NOT 0.0.0.0)"
  if ss -tlnp | grep 18789 | grep -q "127.0.0.1"; then
    echo "OK: Gateway is correctly bound to 127.0.0.1 only."
  elif ss -tlnp | grep -q 18789; then
    echo "WARNING: Gateway is listening but not on 127.0.0.1 - check gateway.bind in openclaw.json." >&2
  else
    echo "Gateway not yet listening - check 'systemctl status openclaw-gateway'." >&2
  fi
}

run_security_audit() {
  print_step "Running OpenClaw security audit"

  echo "Waiting for gateway to be ready (up to 30s)..."
  local elapsed=0
  until sudo -u "${OPENCLAW_USER}" openclaw --version &>/dev/null; do
    if [[ "${elapsed}" -ge 30 ]]; then
      echo "Gateway did not become ready within 30s - skipping automated audit."
      echo "Run manually once it's up:"
      echo "  openclaw doctor --fix"
      echo "  openclaw security audit --deep"
      return
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo ""
  echo "--- openclaw doctor --fix ---"
  sudo -u "${OPENCLAW_USER}" openclaw doctor --fix || true

  echo ""
  echo "--- openclaw security audit --deep ---"
  local audit_exit_code=0
  sudo -u "${OPENCLAW_USER}" openclaw security audit --deep || audit_exit_code=$?

  if [[ "${audit_exit_code}" -ne 0 ]]; then
    echo ""
    echo "WARNING: Security audit returned issues (exit code ${audit_exit_code})." >&2
    echo "         Review the output above and resolve before going live." >&2
  else
    echo ""
    echo "Security audit passed with 0 critical issues."
  fi
}

configure_tailscale_access() {
  print_step "Configuring Tailscale access for Control UI"

  if [[ -n "${OPENCLAW_SKIP_TAILSCALE_AUTH:-}" ]]; then
    echo "OPENCLAW_SKIP_TAILSCALE_AUTH is set, skipping Tailscale authentication."
    return
  fi

  echo ""
  echo "Tailscale provides secure remote access to the Control UI without"
  echo "opening any public ports. Free tier available at tailscale.com."
  echo ""

  local auth_choice
  read -r -p "Authenticate Tailscale now? [Y/n]: " auth_choice
  auth_choice="${auth_choice:-Y}"

  if [[ ! "${auth_choice}" =~ ^[Yy] ]]; then
    echo "Skipped. Run 'tailscale up' later to authenticate."
    return
  fi

  echo "Running 'tailscale up' - follow the printed URL to authenticate..."
  if ! tailscale up; then
    echo "Tailscale authentication did not complete. Run 'tailscale up' later." >&2
    return
  fi

  echo ""
  local serve_choice
  read -r -p "Expose Control UI via Tailscale Serve now? [Y/n]: " serve_choice
  serve_choice="${serve_choice:-Y}"

  if [[ "${serve_choice}" =~ ^[Yy] ]]; then
    tailscale serve https / http://127.0.0.1:18789
    local ts_hostname
    ts_hostname="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || echo "your-machine.tailnet")"
    echo ""
    echo "Control UI is live at: https://${ts_hostname}/"
  fi
}

offer_onboard_wizard() {
  if [[ "${NEEDS_ONBOARD_WIZARD}" != "true" ]]; then
    return
  fi

  print_step "Logging in to ${CHANNEL} channel"

  if [[ -n "${OPENCLAW_SKIP_ONBOARD:-}" ]]; then
    echo "OPENCLAW_SKIP_ONBOARD is set, skipping channel login."
    echo "Run manually later:"
    echo "  openclaw channels login --channel ${CHANNEL}"
    return
  fi

  echo ""
  echo "${CHANNEL} requires OAuth authentication."
  echo "The login wizard will open a URL you need to visit to authorize access."
  echo ""

  local run_choice
  read -r -p "Run the channel login wizard now? [Y/n]: " run_choice
  run_choice="${run_choice:-Y}"

  if [[ "${run_choice}" =~ ^[Yy] ]]; then
    echo ""
    sudo -u "${OPENCLAW_USER}" openclaw channels login --channel "${CHANNEL}" || {
        echo ""
        echo "Channel login exited with an error." >&2
        echo "Run manually later:" >&2
        echo "  openclaw channels login --channel ${CHANNEL}" >&2
      }
  else
    echo "Skipped. Run the channel login later:"
    echo "  openclaw channels login --channel ${CHANNEL}"
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

  echo "Control UI is available at http://127.0.0.1:18789/ (no channel needed)."
  echo "You can chat with your agent there immediately."
  echo ""

  local has_remaining=false

  if ! tailscale status &>/dev/null; then
    has_remaining=true
    echo "Remaining steps:"
    echo ""
    echo "1. Authenticate Tailscale:"
    echo "   tailscale up"
    echo ""
    echo "2. Expose Control UI via Tailscale:"
    echo "   tailscale serve https / http://127.0.0.1:18789"
    echo ""
    echo "   Or via SSH tunnel from your local machine:"
    echo "   ssh -N -L 18789:127.0.0.1:18789 openclaw@<your-server-ip>"
    echo "   Then open: http://127.0.0.1:18789/"
    echo ""
  fi

  case "${CHANNEL}" in
    telegram)
      if grep -q "REPLACE_WITH_BOT_TOKEN" "${OPENCLAW_DATA_DIR}/openclaw.json" 2>/dev/null; then
        has_remaining=true
        echo "Fill in Telegram credentials:"
        echo "  nano ${OPENCLAW_DATA_DIR}/openclaw.json"
        echo ""
      fi
      ;;
    discord)
      if grep -q "REPLACE_WITH_BOT_TOKEN" "${OPENCLAW_DATA_DIR}/openclaw.json" 2>/dev/null; then
        has_remaining=true
        echo "Fill in Discord credentials:"
        echo "  nano ${OPENCLAW_DATA_DIR}/openclaw.json"
        echo ""
      fi
      ;;
    whatsapp | slack)
      if [[ "${NEEDS_ONBOARD_WIZARD}" == "true" ]]; then
        has_remaining=true
        echo "Complete ${CHANNEL} OAuth setup:"
        echo "  openclaw channels login --channel ${CHANNEL}"
        echo ""
      fi
      ;;
    none)
      has_remaining=true
      echo "Configure a messaging channel:"
      echo "  openclaw channels login --channel <channel>"
      echo "  (or edit ${OPENCLAW_DATA_DIR}/openclaw.json manually)"
      echo ""
      ;;
  esac

  echo "Sandbox is off by default. To enable sandboxed tool execution:"
  echo "  1. Build the sandbox image: scripts/sandbox-setup.sh"
  echo "  2. Set sandbox.mode to \"all\" in openclaw.json"
  echo ""

  if [[ "${has_remaining}" != "true" ]]; then
    echo "All steps completed. Your agent is ready to use."
    echo ""
  fi

  echo "Useful commands:"
  echo "  openclaw configure                        - interactive configuration editor"
  echo "  openclaw config set <k> <v>               - set a config value"
  echo "  openclaw channels login --channel <name>  - authenticate an OAuth channel"
  echo "  openclaw channels list                    - show all configured channels"
  echo "  openclaw channels status                  - check channel runtime status"
  echo "  openclaw doctor --fix                     - diagnose and auto-repair issues"
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
  install_node
  install_openclaw
  create_data_directories
  select_ai_provider
  select_channel
  collect_channel_credentials
  store_ai_api_key
  create_openclaw_config
  setup_auto_update_cron
  start_openclaw_daemon
  verify_gateway_binding
  run_security_audit
  configure_tailscale_access
  offer_onboard_wizard
  print_next_steps
}

main
