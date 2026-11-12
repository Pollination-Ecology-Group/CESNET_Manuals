#!/usr/bin/env bash
# ==============================================================================
# mount_cesnet_s3.sh — Mount or unmount CESNET S3 Object Storage as a local folder
# ==============================================================================
# Usage:
#   ./mount_cesnet_s3.sh          # Mounts peg-bucket to ~/cesnet_s3
#   ./mount_cesnet_s3.sh unmount  # Unmounts ~/cesnet_s3
#
# Prerequisites:
#   1. Install s3fs:
#        Ubuntu/Debian: sudo apt update && sudo apt install -y s3fs
#        Fedora:        sudo dnf install -y s3fs-fuse
#        macOS:         brew install --cask macfuse && brew install gromgit/fuse/s3fs-mac
#   2. Create your credentials file (~/.passwd-s3fs):
#        printf 'YOUR_ACCESS_KEY:YOUR_SECRET_KEY' > ~/.passwd-s3fs
#        chmod 600 ~/.passwd-s3fs
# ==============================================================================

set -euo pipefail

BUCKET_NAME="${CESNET_S3_BUCKET:-peg-bucket}"
S3_ENDPOINT="${CESNET_S3_ENDPOINT:-https://s3.cl4.du.cesnet.cz}"
MOUNT_DIR="${CESNET_S3_MOUNT_DIR:-${HOME}/cesnet_s3}"
PASSWD_FILE="${HOME}/.passwd-s3fs"

if [[ "${1:-}" == "unmount" || "${1:-}" == "umount" ]]; then
    echo "Unmounting ${MOUNT_DIR}..."
    if command -v fusermount >/dev/null 2>&1; then
        fusermount -u "${MOUNT_DIR}"
    else
        umount "${MOUNT_DIR}"
    fi
    echo "Done! ${MOUNT_DIR} is unmounted."
    exit 0
fi

# 1. Verify s3fs is installed
if ! command -v s3fs >/dev/null 2>&1; then
    echo "Error: 's3fs' is not installed."
    echo "Install it on Ubuntu/Debian with: sudo apt install -y s3fs"
    exit 1
fi

# 2. Verify ~/.passwd-s3fs exists and has 600 permissions
if [[ ! -f "${PASSWD_FILE}" ]]; then
    echo "Error: Credentials file ${PASSWD_FILE} not found!"
    echo "Create it by running:"
    echo "  printf 'YOUR_ACCESS_KEY:YOUR_SECRET_KEY' > ~/.passwd-s3fs"
    echo "  chmod 600 ~/.passwd-s3fs"
    exit 1
fi

chmod 600 "${PASSWD_FILE}"

# 3. Create mount directory and mount
mkdir -p "${MOUNT_DIR}"

if mountpoint -q "${MOUNT_DIR}" 2>/dev/null; then
    echo "Notice: ${MOUNT_DIR} is already mounted."
    exit 0
fi

echo "Mounting CESNET S3 bucket '${BUCKET_NAME}' (${S3_ENDPOINT}) to ${MOUNT_DIR}..."
s3fs "${BUCKET_NAME}" "${MOUNT_DIR}" \
    -o passwd_file="${PASSWD_FILE}" \
    -o url="${S3_ENDPOINT}" \
    -o use_path_request_style \
    -o uid="$(id -u)" \
    -o gid="$(id -g)" \
    -o umask=0022

echo "Success! You can now browse files at: ${MOUNT_DIR}"
echo "To unmount later, run: $0 unmount"

