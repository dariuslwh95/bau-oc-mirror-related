import os
import re
import subprocess
import sys

# Constants for your 1TB EBS volume
STORAGE_PATH = "/mnt/mirror-data/gaia-operators"
# CACHE_DIR = "/mnt/mirror-data/oc-mirror-cache"
MAX_RETRY_COUNT = 20

def is_tar_file_created():
    """Checks for .tar files on the 1TB EBS volume."""
    if not os.path.exists(STORAGE_PATH):
        return False
    storage_path_contents = os.listdir(STORAGE_PATH)
    for content in storage_path_contents:
        if re.search(r".tar$", content):
            return True
    return False

def run_mirroring(isc_path):
    # Log file resides on the 1TB persistent storage
    log_file_path = os.path.join(STORAGE_PATH, "oc-mirror-execution.log")
    
    # We use 'tee' to split the output to both STDOUT and the Log File
    # '2>&1' ensures errors are caught in the log as well
    mirror_command = (
        f"oc-mirror --v1 --config={isc_path} "
        f"file://{STORAGE_PATH} 2>&1 | tee {log_file_path}"
    )
    
    print(f"--- Initialization ---")
    print(f"Config: {isc_path}")
    print(f"Storage: {STORAGE_PATH}")
    print(f"Log: {log_file_path}")

    # Ensure the directory exists before writing
    if not os.path.exists(STORAGE_PATH):
        os.makedirs(STORAGE_PATH)

    for retry_count in range(1, MAX_RETRY_COUNT + 1):
        print(f"\n--- Download Attempt {retry_count} ---")
        
        # subprocess.run with shell=True executes the tee command
        subprocess.run(mirror_command, shell=True, executable="/bin/bash")
        
        if is_tar_file_created():
            print(f"\n✅ SUCCESS: Mirroring completed after {retry_count} attempts.")
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