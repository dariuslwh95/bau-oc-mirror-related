#!/bin/bash

# --- Configuration ---
REPO_BASE="/home/ssm-user/bau-oc-mirror-related"
INBOX_DIR="${REPO_BASE}/inbox"
ARCHIVE_DIR="${REPO_BASE}/archive"
BASE_STORAGE="/mnt/mirror-data"
DATE_SUFFIX=$(date +%Y%m%d)

# Validate Input
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <isc-filename.yaml> <v1|v2>"
    exit 1
fi

ISC_FILE="$1"
MIRROR_VER="$2"
ISC_PATH="${INBOX_DIR}/${ISC_FILE}"
BASE_NAME=$(basename "$ISC_FILE" .yaml)

# Set Version-Specific Paths
CACHE_DIR="${BASE_STORAGE}/.cache-${MIRROR_VER}"
# Directory structure: /mnt/mirror-data/output-v2/imageset-name-20260509
DEST_DIR="${BASE_STORAGE}/output-${MIRROR_VER}/${BASE_NAME}-${DATE_SUFFIX}"

if [ ! -f "$ISC_PATH" ]; then
    echo "ERROR: File $ISC_PATH not found in inbox."
    exit 1
fi

# Setup Workspace
TMP_WORK_DIR="${DEST_DIR}/tmp_hold"
mkdir -p "$TMP_WORK_DIR" "$ARCHIVE_DIR" "$DEST_DIR" "$CACHE_DIR"

echo "=========================================================="
echo "STARTING MIRROR ($MIRROR_VER): $ISC_FILE"
echo "=========================================================="

if [ "$MIRROR_VER" == "v2" ]; then
    oc-mirror --config "$ISC_PATH" --cache-dir "$CACHE_DIR" "file://${TMP_WORK_DIR}" --v2
else
    oc-mirror --config "$ISC_PATH" --cache-dir "$CACHE_DIR" "file://${TMP_WORK_DIR}"
fi

STATUS=$?

if [ $STATUS -eq 0 ]; then
    echo "oc-mirror succeeded. Processing chunks..."
    
    CHUNK_COUNT=1
    # Sort ensures we process sequence 1, then 2, etc.
    find "$TMP_WORK_DIR" -type f -name "*.tar" | sort | while read -r FILE; do
        
        # Consistent naming for S3 clarity
        FINAL_TAR="${DEST_DIR}/${BASE_NAME}-${MIRROR_VER}-chunk${CHUNK_COUNT}.tar"
        
        echo "Moving Chunk: $(basename "$FINAL_TAR")"
        mv "$FILE" "$FINAL_TAR"
        
        echo "Generating Checksum..."
        # Extract only the hash for a clean .sha256 file
        sha256sum "$FINAL_TAR" | awk '{print $1}' > "${FINAL_TAR}.sha256"
        
        ((CHUNK_COUNT++))
    done

    # Cleanup temporary layout
    rm -rf "$TMP_WORK_DIR"
    
    echo "=========================================================="
    echo "COMPLETE: Files ready for S3 upload"
    echo "Location: $DEST_DIR"
    echo "=========================================================="
else
    echo "ERROR: Mirror failed. Data preserved in $TMP_WORK_DIR"
    exit $STATUS
fi