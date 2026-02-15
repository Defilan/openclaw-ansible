#!/bin/bash
# OpenClaw Google Drive Sync Script - Managed by Ansible
set -euo pipefail

BACKUP_DIR="${OPENCLAW_BACKUP_DIR:-$HOME/backups}"
GDRIVE_DEST="${OPENCLAW_GDRIVE_DEST:-OpenClaw-Backups}"
RCLONE_REMOTE="${OPENCLAW_RCLONE_REMOTE:-gdrive}"

# Sync backups to Google Drive
if command -v rclone &> /dev/null; then
    rclone sync "${BACKUP_DIR}" "${RCLONE_REMOTE}:${GDRIVE_DEST}" \
        --include "openclaw-backup-*.tar.gz" \
        --log-level INFO
    echo "Backups synced to Google Drive: ${GDRIVE_DEST}"
else
    echo "ERROR: rclone not installed. Install with: brew install rclone"
    exit 1
fi
