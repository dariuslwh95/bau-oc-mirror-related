#!/bin/bash

# --- Configuration ---
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
CHECKSUM_FILE_NAME="${BASE_NAME}-${DATE_SUFFIX}.txt"
CHECKSUM_PATH="${DEST_DIR}/${CHECKSUM_FILE_NAME}"

if [ ! -f "$ISC_PATH" ]; then
    echo "ERROR: File not found: $ISC_PATH"
    exit 1
fi

# Setup Workspace
TMP_WORK_DIR="${DEST_DIR}/tmp_hold"
mkdir -p "$TMP_WORK_DIR" "$DEST_DIR"

echo "=========================================================="
echo "STARTING MIRROR ($MIRROR_VER): $ISC_FILE"
echo "=========================================================="

# Copy the ISC YAML into the output folder for retention
cp "$ISC_PATH" "${DEST_DIR}/${ISC_FILE}"

if [ "$MIRROR_VER" == "v2" ]; then
    CACHE_DIR="${BASE_STORAGE}/.cache-v2"
    mkdir -p "$CACHE_DIR"
    oc-mirror --v2 --config "$ISC_PATH" --cache-dir "$CACHE_DIR" "file://${TMP_WORK_DIR}"
else
    V1_WORKSPACE="${BASE_STORAGE}/.workspace-v1"
    mkdir -p "$V1_WORKSPACE"
    
    pushd "$V1_WORKSPACE" > /dev/null
    oc-mirror --v1 --config "$ISC_PATH" "file://${TMP_WORK_DIR}"
    
    if [ -f ".oc-mirror.log" ]; then
        mv ".oc-mirror.log" "${DEST_DIR}/${BASE_NAME}-${DATE_SUFFIX}.log"
    fi
    popd > /dev/null
fi

STATUS=$?

if [ $STATUS -eq 0 ]; then
    echo "oc-mirror succeeded. Generating checksums..."
    
    # Initialize/Clear the manifest file
    > "$CHECKSUM_PATH"

    # Find archives, move them to DEST_DIR, and hash them
    find "$TMP_WORK_DIR" -type f -name "*.tar" | sort | while read -r FILE; do
        TAR_FILENAME=$(basename "$FILE")
        
        echo "Processing $TAR_FILENAME..."
        
        # Move the file from tmp to final destination using original name
        mv "$FILE" "${DEST_DIR}/${TAR_FILENAME}"
        
        # Calculate MD5 and append to manifest
        (cd "$DEST_DIR" && md5sum "$TAR_FILENAME" >> "$CHECKSUM_FILE_NAME")
    done

    # Clean up the empty temporary directory
    rm -rf "$TMP_WORK_DIR"
    
    echo "=========================================================="
    echo "COMPLETE"
    echo "Folder content: Original Tarballs, Logs, ISC.yaml, and Checksums"
    echo "Manifest: $CHECKSUM_PATH"
    echo "Location: $DEST_DIR"
    echo "=========================================================="
else
    if [ "$MIRROR_VER" == "v1" ] && [ -f "${V1_WORKSPACE}/.oc-mirror.log" ]; then
        cp "${V1_WORKSPACE}/.oc-mirror.log" "${DEST_DIR}/${BASE_NAME}-${DATE_SUFFIX}-FAILED.log"
    fi
    echo "ERROR: Mirror failed with exit code $STATUS."
    exit $STATUS
fi