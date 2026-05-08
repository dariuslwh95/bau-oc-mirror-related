#!/bin/bash

# --- Paths ---
# Git Repo Directories
REPO_BASE="/home/ssm-user/bau-oc-mirror-related"
INBOX_DIR="${REPO_BASE}/inbox"
ARCHIVE_DIR="${REPO_BASE}/archive"

# EBS Volume Storage (4TB)
BASE_STORAGE="/mnt/mirror-data"
WORKSPACE="${BASE_STORAGE}/workspace"
CACHE_DIR="${BASE_STORAGE}/.cache"
DEST_DIR="${BASE_STORAGE}/output"

# Metadata & Naming
DATE_SUFFIX=$(date +%Y%m%d)

# Create directories if they don't exist
mkdir -p "$INBOX_DIR" "$ARCHIVE_DIR" "$WORKSPACE" "$DEST_DIR" "$CACHE_DIR"

# Check if there are any yaml files to process
shopt -s nullglob
files=("$INBOX_DIR"/*.yaml)

if [ ${#files[@]} -eq 0 ]; then
    echo "No new ISC files found in $INBOX_DIR. Exiting."
    exit 0
fi

for isc_path in "${files[@]}"; do
    isc_file=$(basename "$isc_path")
    BASE_NAME=$(basename "$isc_file" .yaml)
    TARGET_TARBALL="${DEST_DIR}/${BASE_NAME}-${DATE_SUFFIX}.tar"
    
    echo "=========================================================="
    echo "PROCESSING NEW ISC: $isc_file"
    echo "=========================================================="

    # Run oc-mirror v2
    # Workspace persists on EBS so future runs of the same filename are incremental
    oc-mirror --config "$isc_path" \
              --cache-dir "$CACHE_DIR" \
              --workspace "file://${WORKSPACE}/${BASE_NAME}" \
              "file://${DEST_DIR}/${BASE_NAME}_tmp" \
              --v2

    # Check for the generated tarball
    GENERIC_TAR=$(find "${DEST_DIR}/${BASE_NAME}_tmp" -name "mirror_seq*.tar" | head -n 1)

    if [ -f "$GENERIC_TAR" ]; then
        # 1. Finalize the Tarball on EBS
        mv "$GENERIC_TAR" "$TARGET_TARBALL"
        sha256sum "$TARGET_TARBALL" > "${TARGET_TARBALL}.sha256"
        
        # 2. Archive the ISC YAML in Git
        # We append the date to the archived YAML to keep a history of what ran when
        mv "$isc_path" "${ARCHIVE_DIR}/${BASE_NAME}-${DATE_SUFFIX}.yaml"
        
        # 3. Cleanup temp folder
        rm -rf "${DEST_DIR}/${BASE_NAME}_tmp"
        
        echo "SUCCESS: Tarball created at $TARGET_TARBALL"
        echo "SUCCESS: ISC moved to $ARCHIVE_DIR"
    else
        echo "FAILED: Mirroring failed for $isc_file. Leaving in inbox for retry."
    fi
done

echo "=========================================================="
echo "Run complete. Remember to commit your archived YAMLs to Git."