#!/usr/bin/env bash
set -euo pipefail
umask 077

OPENCLAW_DATA_DIR="/home/openclaw/.openclaw"
BACKUP_DIR="/home/openclaw/backups"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
  fi
}

list_backups() {
  local backups=()
  mapfile -t backups < <(ls -t "${BACKUP_DIR}"/openclaw-backup-*.tar.gz 2>/dev/null) || true

  if [[ ${#backups[@]} -eq 0 ]]; then
    echo "No backups found in ${BACKUP_DIR}" >&2
    exit 1
  fi

  echo "Available backups (newest first):"
  echo ""
  local i=1
  for b in "${backups[@]}"; do
    local size
    size="$(du -h "$b" | awk '{print $1}')"
    local date_part
    date_part="$(basename "$b" | sed 's/openclaw-backup-//;s/\.tar\.gz//')"
    echo "  ${i}) $(basename "$b")  (${size}, ${date_part})"
    i=$((i + 1))
  done
  echo ""
}

select_backup() {
  local backups=()
  mapfile -t backups < <(ls -t "${BACKUP_DIR}"/openclaw-backup-*.tar.gz 2>/dev/null) || true

  if [[ -n "${1:-}" ]]; then
    if [[ -f "$1" ]]; then
      SELECTED_BACKUP="$1"
      return
    fi
    for b in "${backups[@]}"; do
      if [[ "$(basename "$b")" == "$1" ]]; then
        SELECTED_BACKUP="$b"
        return
      fi
    done
    echo "Backup not found: $1" >&2
    exit 1
  fi

  if [[ ${#backups[@]} -eq 1 ]]; then
    SELECTED_BACKUP="${backups[0]}"
    echo "Only one backup available, selecting: $(basename "${SELECTED_BACKUP}")"
    return
  fi

  local choice
  read -r -p "Enter backup number [1 = latest]: " choice
  choice="${choice:-1}"

  if [[ "${choice}" -lt 1 ]] || [[ "${choice}" -gt ${#backups[@]} ]]; then
    echo "Invalid selection." >&2
    exit 1
  fi

  SELECTED_BACKUP="${backups[$((choice - 1))]}"
  echo "Selected: $(basename "${SELECTED_BACKUP}")"
}

validate_backup() {
  echo "Validating backup integrity..."
  if ! tar -tzf "${SELECTED_BACKUP}" &>/dev/null; then
    echo "Backup archive is corrupt or unreadable: ${SELECTED_BACKUP}" >&2
    exit 1
  fi

  if ! tar -tzf "${SELECTED_BACKUP}" | grep -q "openclaw.json" 2>/dev/null; then
    echo "WARNING: Backup does not appear to contain openclaw.json." >&2
    local proceed
    read -r -p "Continue anyway? [y/N]: " proceed
    if [[ ! "${proceed}" =~ ^[Yy] ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  echo "Backup validated."
}

restore() {
  echo ""
  echo "Stopping openclaw-gateway..."
  systemctl stop openclaw-gateway 2>/dev/null || true

  local pre_restore_backup
  pre_restore_backup="${BACKUP_DIR}/pre-restore-$(date +%Y%m%d-%H%M%S).tar.gz"
  echo "Saving current state to $(basename "${pre_restore_backup}")..."
  if [[ -d "${OPENCLAW_DATA_DIR}" ]]; then
    tar -czf "${pre_restore_backup}" -C / "${OPENCLAW_DATA_DIR#/}" 2>/dev/null || true
    chmod 600 "${pre_restore_backup}"
    chown root:root "${pre_restore_backup}"
  fi

  echo "Restoring from $(basename "${SELECTED_BACKUP}")..."
  tar -xzf "${SELECTED_BACKUP}" -C /

  chown -R openclaw:openclaw "${OPENCLAW_DATA_DIR}"
  chmod 700 "${OPENCLAW_DATA_DIR}"
  find "${OPENCLAW_DATA_DIR}" -type f -exec chmod 600 {} +
  find "${OPENCLAW_DATA_DIR}" -type d -exec chmod 700 {} +

  echo "Starting openclaw-gateway..."
  systemctl start openclaw-gateway 2>/dev/null || true

  echo ""
  echo "Restore complete."
  echo "Pre-restore snapshot saved to: ${pre_restore_backup}"
  echo "Run 'openclaw doctor --fix' to verify the restored configuration."
}

main() {
  require_root

  echo "OpenClaw Backup Restore"
  echo "======================"
  echo ""

  list_backups
  select_backup "${1:-}"
  validate_backup
  restore
}

main "$@"
