#!/bin/bash
# OpenClaw Backup Script - Managed by Ansible
set -euo pipefail

BACKUP_DIR="${OPENCLAW_BACKUP_DIR:-$HOME/backups}"
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
RETENTION_DAYS="${OPENCLAW_BACKUP_RETENTION:-30}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/openclaw-backup-${TIMESTAMP}.tar.gz"

# Create backup directory if needed
mkdir -p "${BACKUP_DIR}"

# Create backup of .openclaw directory
# NOTE: This backup is NOT encrypted. If syncing to cloud storage, consider
# wrapping with gpg: tar czf - ... | gpg --batch -c -o backup.tar.gz.gpg
tar czf "${BACKUP_FILE}" -C "$(dirname "${CONFIG_DIR}")" "$(basename "${CONFIG_DIR}")"

# Set restrictive permissions
chmod 600 "${BACKUP_FILE}"

echo "Backup created: ${BACKUP_FILE}"
echo "Size: $(du -h "${BACKUP_FILE}" | cut -f1)"

# Clean up old backups
find "${BACKUP_DIR}" -name "openclaw-backup-*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

echo "Cleaned up backups older than ${RETENTION_DAYS} days"
