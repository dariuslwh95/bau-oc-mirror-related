#!/bin/bash

# --- Configuration ---
# Resolves the absolute path of the directory where the script is located, 
# then goes up one level to the repo root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_BASE="$(dirname "$SCRIPT_DIR")"

INBOX_DIR="${REPO_BASE}/inbox"
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
DEST_DIR="${BASE_STORAGE}/output-${MIRROR_VER}/${BASE_NAME}-${DATE_SUFFIX}"

if [ ! -f "$ISC_PATH" ]; then
    echo "ERROR: File not found: $ISC_PATH"
    echo "Make sure your YAML is in: $INBOX_DIR"
    exit 1
fi

# Setup Workspace
TMP_WORK_DIR="${DEST_DIR}/tmp_hold"
mkdir -p "$TMP_WORK_DIR" "$DEST_DIR"

echo "=========================================================="
echo "STARTING MIRROR ($MIRROR_VER): $ISC_FILE"
echo "REPO_BASE: $REPO_BASE"
echo "=========================================================="

if [ "$MIRROR_VER" == "v2" ]; then
    # v2 uses the explicit --cache-dir flag
    CACHE_DIR="${BASE_STORAGE}/.cache-v2"
    mkdir -p "$CACHE_DIR"
    oc-mirror --config "$ISC_PATH" --cache-dir "$CACHE_DIR" "file://${TMP_WORK_DIR}" --v2
else
    # v1 manages its own workspace. 
    V1_WORKSPACE="${BASE_STORAGE}/.workspace-v1"
    mkdir -p "$V1_WORKSPACE"
    
    pushd "$V1_WORKSPACE" > /dev/null
    oc-mirror --config "$ISC_PATH" "file://${TMP_WORK_DIR}"
    popd > /dev/null
fi

STATUS=$?

if [ $STATUS -eq 0 ]; then
    echo "oc-mirror succeeded. Processing chunks..."
    
    CHUNK_COUNT=1
    find "$TMP_WORK_DIR" -type f -name "*.tar" | sort | while read -r FILE; do
        
        FINAL_TAR="${DEST_DIR}/${BASE_NAME}-${MIRROR_VER}-chunk${CHUNK_COUNT}.tar"
        
        echo "Moving Chunk: $(basename "$FINAL_TAR")"
        mv "$FILE" "$FINAL_TAR"
        
        echo "Generating Checksum..."
        sha256sum "$FINAL_TAR" | awk '{print $1}' > "${FINAL_TAR}.sha256"
        
        ((CHUNK_COUNT++))
    done

    # Cleanup temporary layout
    rm -rf "$TMP_WORK_DIR"
    
    echo "=========================================================="
    echo "COMPLETE: Files ready for S3 sync"
    echo "Location: $DEST_DIR"
    echo "=========================================================="
else
    echo "ERROR: Mirror failed. Data preserved in $TMP_WORK_DIR"
    exit $STATUS
fi