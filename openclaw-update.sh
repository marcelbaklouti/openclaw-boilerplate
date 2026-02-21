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

  local backup_filename="${BACKUP_DIR}/openclaw-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "${backup_filename}" "${OPENCLAW_DATA_DIR}"
  chmod 600 "${backup_filename}"
  chown root:root "${backup_filename}"
  log "Backup created: ${backup_filename}"
}

prune_old_backups() {
  find "${BACKUP_DIR}" -maxdepth 1 -name "openclaw-backup-*.tar.gz" -mtime "+${BACKUP_RETENTION_DAYS}" -delete
  log "Backups older than ${BACKUP_RETENTION_DAYS} days pruned"
}

update_npm_package() {
  npm install -g openclaw@latest >> "${LOG_FILE}" 2>&1
  log "openclaw npm package updated to latest"
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
  update_npm_package
  rebuild_and_restart_container
  log "Update complete"
}

main
