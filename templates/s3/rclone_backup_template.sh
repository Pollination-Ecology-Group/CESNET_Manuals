#!/usr/bin/env bash
# ==============================================================================
# rclone_backup_template.sh — Fast, parallel copy/backup to CESNET S3 via rclone
# ==============================================================================
# Why use rclone instead of s3fs?
#   When transferring hundreds of photos, microscopy scans, or large archives,
#   rclone transfers multiple files in parallel and verifies checksums directly
#   against the S3 API (10x-50x faster than copying into an s3fs mount).
#
# Prerequisites:
#   1. Install rclone: sudo apt install -y rclone (or https://rclone.org/install/)
#   2. Configure a remote named 'cesnet-s3' in ~/.config/rclone/rclone.conf:
#
#      [cesnet-s3]
#      type = s3
#      provider = Ceph
#      access_key_id = YOUR_ACCESS_KEY
#      secret_access_key = YOUR_SECRET_KEY
#      endpoint = https://s3.cl4.du.cesnet.cz
#      acl = private
# ==============================================================================

set -euo pipefail

# --- Configuration (Edit these paths for your project) ---
LOCAL_SOURCE_DIR="${1:-/path/to/your/local_folder}"
S3_REMOTE_DEST="${2:-cesnet-s3:peg-bucket/Ostatni/YourName_ProjectBackup}"
LOG_FILE="/tmp/rclone_cesnet_$(date +%Y%m%d_%H%M%S).log"

if [[ "${LOCAL_SOURCE_DIR}" == "/path/to/your/local_folder" ]]; then
    echo "Usage:"
    echo "  ./rclone_backup_template.sh <LOCAL_SOURCE_DIR> <S3_REMOTE_DEST>"
    echo ""
    echo "Example:"
    echo "  ./rclone_backup_template.sh ~/Data/FieldSeason2026 cesnet-s3:peg-bucket/Ostatni/FieldSeason2026"
    exit 1
fi

if [[ ! -d "${LOCAL_SOURCE_DIR}" ]]; then
    echo "Error: Local source directory '${LOCAL_SOURCE_DIR}' does not exist."
    exit 1
fi

echo "============================================================"
echo "Starting Rclone upload to CESNET S3"
echo "  Source:      ${LOCAL_SOURCE_DIR}"
echo "  Destination: ${S3_REMOTE_DEST}"
echo "  Log file:    ${LOG_FILE}"
echo "============================================================"

# NOTE: We use 'rclone copy' (NOT 'rclone sync') so that files deleted locally
# are NEVER accidentally deleted from the shared CESNET S3 bucket.
rclone copy "${LOCAL_SOURCE_DIR}" "${S3_REMOTE_DEST}" \
    --update \
    --transfers 16 \
    --checkers 16 \
    --fast-list \
    --s3-chunk-size 64M \
    --s3-upload-concurrency 8 \
    --progress \
    --log-file="${LOG_FILE}" \
    --log-level INFO

echo "============================================================"
echo "Upload complete! Full log saved to: ${LOG_FILE}"
echo "============================================================"

