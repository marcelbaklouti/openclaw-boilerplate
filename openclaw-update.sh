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
  local old_version
  old_version="$(openclaw --version 2>/dev/null || echo 'unknown')"
  log "Current version before update: ${old_version}"

  npm update -g openclaw@latest >> "${LOG_FILE}" 2>&1

  local new_version
  new_version="$(openclaw --version 2>/dev/null || echo 'unknown')"
  log "Version after update: ${new_version}"

  systemctl restart openclaw-gateway >> "${LOG_FILE}" 2>&1
  log "OpenClaw updated and gateway restarted"
}

run_post_update_audit() {
  log "Running post-update security audit"
  local openclaw_user="openclaw"
  sudo -u "${openclaw_user}" openclaw doctor --fix >> "${LOG_FILE}" 2>&1 || true
  sudo -u "${openclaw_user}" openclaw security audit --deep >> "${LOG_FILE}" 2>&1 || {
    log "WARNING: Post-update security audit reported issues - review ${LOG_FILE}"
  }
}

main() {
  require_root
  acquire_lock
  log "Starting OpenClaw update"
  create_backup
  prune_old_backups
  update_and_restart
  run_post_update_audit
  log "Update complete"
}

main
