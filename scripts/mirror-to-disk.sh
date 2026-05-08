#!/bin/bash

# --- Configuration ---
REPO_BASE="/home/ssm-user/bau-oc-mirror-related"
INBOX_DIR="${REPO_BASE}/inbox"
ARCHIVE_DIR="${REPO_BASE}/archive"

BASE_STORAGE="/mnt/mirror-data"
CACHE_DIR="${BASE_STORAGE}/.cache"
DEST_DIR="${BASE_STORAGE}/output"
DATE_SUFFIX=$(date +%Y%m%d)

# Validate Input
if [ -z "$1" ]; then
    echo "Usage: $0 <isc-filename.yaml>"
    echo "Example: $0 imageset-4.19-operators.yaml"
    exit 1
fi

ISC_FILE="$1"
ISC_PATH="${INBOX_DIR}/${ISC_FILE}"
BASE_NAME=$(basename "$ISC_FILE" .yaml)

if [ ! -f "$ISC_PATH" ]; then
    echo "ERROR: File $ISC_PATH not found in inbox."
    exit 1
fi

# Setup Temporary Workspace
TMP_WORK_DIR="${DEST_DIR}/${BASE_NAME}_tmp"
mkdir -p "$TMP_WORK_DIR" "$ARCHIVE_DIR" "$DEST_DIR" "$CACHE_DIR"

echo "=========================================================="
echo "STARTING MIRROR: $ISC_FILE"
echo "=========================================================="

# Run oc-mirror
# Removed --workspace as v2 handles this automatically in the destination for file://
oc-mirror --config "$ISC_PATH" \
          --cache-dir "$CACHE_DIR" \
          "file://${TMP_WORK_DIR}" \
          --v2

# Capture the exit code of the oc-mirror command
STATUS=$?

if [ $STATUS -eq 0 ]; then
    echo "oc-mirror command succeeded. Processing tarballs..."
    
    # Find all generated tarballs (v2 often creates 00001.tar, 00002.tar, etc.)
    mapfile -t TAR_FILES < <(find "$TMP_WORK_DIR" -type f -name "*.tar")

    if [ ${#TAR_FILES[@]} -gt 0 ]; then
        for FILE in "${TAR_FILES[@]}"; do
            SEQ=$(basename "$FILE" .tar)
            FINAL_NAME="${DEST_DIR}/${BASE_NAME}-${DATE_SUFFIX}-${SEQ}.tar"
            
            mv "$FILE" "$FINAL_NAME"
            echo "Generating Checksum for $(basename "$FINAL_NAME")..."
            sha256sum "$FINAL_NAME" > "${FINAL_NAME}.sha256"
        done
        
        # remove working directory
        rm -rf "$TMP_WORK_DIR"
        
        echo "=========================================================="
        echo "COMPLETE: ISC archived and tarballs ready in $DEST_DIR"
        echo "=========================================================="
    else
        echo "ERROR: oc-mirror exited 0 but no tarballs were found in $TMP_WORK_DIR"
        exit 1
    fi
else
    echo "ERROR: oc-mirror failed with exit code $STATUS."
    echo "Temporary data preserved at: $TMP_WORK_DIR"
    exit $STATUS
fi