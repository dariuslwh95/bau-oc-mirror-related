import os
import re
import subprocess
import sys
from pathlib import Path

# Constants for your 1TB EBS volume
BASE_STORAGE_PATH = "/mnt/mirror-data/gaia-operators"
MAX_RETRY_COUNT = 20

def is_tar_file_created(storage_path):
    """Checks for .tar files in the specific ISC storage path."""
    if not os.path.exists(storage_path):
        return False
    storage_path_contents = os.listdir(storage_path)
    for content in storage_path_contents:
        if re.search(r".tar$", content):
            return True
    return False

def run_mirroring(isc_path):
    # 1. Extract the name without .yaml (e.g., 'imageset-4.20-operators')
    isc_name = Path(isc_path).stem
    
    # 2. Create a dedicated sub-directory for this specific mirror run
    specific_storage_path = os.path.join(BASE_STORAGE_PATH, isc_name)
    log_file_path = os.path.join(specific_storage_path, "oc-mirror-execution.log")
    
    print(f"--- Initialization ---")
    print(f"Config: {isc_path}")
    print(f"Output Directory: {specific_storage_path}")
    print(f"Log: {log_file_path}")

    # Ensure the dedicated directory exists
    if not os.path.exists(specific_storage_path):
        os.makedirs(specific_storage_path)

    # 3. Update the command to use the new specific_storage_path
    mirror_command = (
        f"oc-mirror --v1 --config={isc_path} "
        f"file://{specific_storage_path} 2>&1 | tee {log_file_path}"
    )
    
    for retry_count in range(1, MAX_RETRY_COUNT + 1):
        print(f"\n--- Download Attempt {retry_count} ---")
        
        subprocess.run(mirror_command, shell=True, executable="/bin/bash")
        
        if is_tar_file_created(specific_storage_path):
            print(f"\n✅ SUCCESS: Mirroring completed after {retry_count} attempts.")
            # Optional: Add S3 upload call here
            return
            
        print(f"\n⚠️ WARNING: Attempt {retry_count} failed to create tarballs. Retrying...")

    print("\n❌ CRITICAL: Mirroring failed after maximum retries.")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 main.py <path_to_imageset_config.yaml>")
        sys.exit(1)
    
    isc_path = sys.argv[1]
    
    if not os.path.exists(isc_path):
        print(f"Error: File {isc_path} not found.")
        sys.exit(1)
        
    run_mirroring(isc_path)

if __name__ == "__main__":
    main()