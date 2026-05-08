#!/bin/bash

# --- Paths ---
REPO_BASE="/home/ssm-user/bau-oc-mirror-related"
INBOX_DIR="${REPO_BASE}/inbox"
ARCHIVE_DIR="${REPO_BASE}/archive"

BASE_STORAGE="/mnt/mirror-data"
WORKSPACE="${BASE_STORAGE}/workspace"
CACHE_DIR="${BASE_STORAGE}/.cache"
DEST_DIR="${BASE_STORAGE}/output"

DATE_SUFFIX=$(date +%Y%m%d)

# Ensure directories exist
mkdir -p "$INBOX_DIR" "$ARCHIVE_DIR" "$WORKSPACE" "$DEST_DIR" "$CACHE_DIR"

shopt -s nullglob
files=("$INBOX_DIR"/*.yaml)

if [ ${#files[@]} -eq 0 ]; then
    echo "No files in $INBOX_DIR. Standing by..."
    exit 0
fi

for isc_path in "${files[@]}"; do
    isc_file=$(basename "$isc_path")
    BASE_NAME=$(basename "$isc_file" .yaml)
    
    # We will create a unique temporary directory for this specific run
    TMP_WORK_DIR="${DEST_DIR}/${BASE_NAME}_tmp_${DATE_SUFFIX}"
    mkdir -p "$TMP_WORK_DIR"
    
    TARGET_TARBALL="${DEST_DIR}/${BASE_NAME}-${DATE_SUFFIX}.tar"
    
    echo "=========================================================="
    echo "STARTING: $isc_file"
    echo "TEMP DIR: $TMP_WORK_DIR"
    echo "=========================================================="

    # Run oc-mirror
    # We point oc-mirror to the TMP_WORK_DIR directly
    oc-mirror --config "$isc_path" \
              --cache-dir "$CACHE_DIR" \
              --workspace "file://${WORKSPACE}/${BASE_NAME}" \
              "file://${TMP_WORK_DIR}" \
              --v2

    # Debug: List what was actually created if it fails
    echo "Scanning for generated tarball..."
    
    # Search recursively for any .tar file inside the temp work dir
    GENERIC_TAR=$(find "$TMP_WORK_DIR" -type f -name "mirror_seq*.tar" | head -n 1)

    if [ -n "$GENERIC_TAR" ] && [ -f "$GENERIC_TAR" ]; then
        echo "Found tarball: $GENERIC_TAR"
        
        # 1. Move and rename
        mv "$GENERIC_TAR" "$TARGET_TARBALL"
        
        # 2. Checksum
        echo "Generating SHA256..."
        sha256sum "$TARGET_TARBALL" > "${TARGET_TARBALL}.sha256"
        
        # 3. Archive the ISC
        mv "$isc_path" "${ARCHIVE_DIR}/${BASE_NAME}-${DATE_SUFFIX}.yaml"
        
        # 4. Clean up the temp dir
        rm -rf "$TMP_WORK_DIR"
        
        echo "SUCCESS: Created $TARGET_TARBALL"
    else
        echo "ERROR: oc-mirror finished but no mirror_seq*.tar was found in $TMP_WORK_DIR"
        echo "Contents of temp dir for debugging:"
        ls -R "$TMP_WORK_DIR"
        # We don't delete the folder here so you can inspect what went wrong
    fi
done