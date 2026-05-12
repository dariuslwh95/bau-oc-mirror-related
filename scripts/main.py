import os
import re
import subprocess
import sys

# Replace these variables to match your environment
STORAGE_PATH = "/mnt/mirror-data/gaia-operators"
# CACHE_DIR = "/mnt/mirror-data/oc-mirror-cache"
MAX_RETRY_COUNT = 20

def is_tar_file_created():
    """Checks if any .tar file exists in the storage path."""
    if not os.path.exists(STORAGE_PATH):
        return False
    storage_path_contents = os.listdir(STORAGE_PATH)
    for content in storage_path_contents:
        if re.search(r".tar$", content):
            return True
    return False

def run_mirroring(isc_path):
    # Log file will be saved directly to your 1TB EBS volume
    log_file_path = os.path.join(STORAGE_PATH, "oc-mirror-execution.log")
    
    # Constructing the command
    # Added --cache-dir and redirecting both stdout and stderr to the log file
    mirror_command = (
        f"oc-mirror --v1 --config={isc_path} "
        f"file://{STORAGE_PATH}" # --cache-dir={CACHE_DIR} "
        f"--log-level=debug > {log_file_path} 2>&1"
    )
    
    print(f"Running mirror with config: {isc_path}")
    print(f"Logs will be written to: {log_file_path}")

    if not os.path.exists(STORAGE_PATH):
        os.makedirs(STORAGE_PATH)

    for retry_count in range(1, MAX_RETRY_COUNT + 1):
        print(f"Download attempt {retry_count}...")
        
        # subprocess.run will wait for the command to finish
        subprocess.run(mirror_command, shell=True, executable="/bin/bash")
        
        if is_tar_file_created():
            print(f"✅ Mirroring completed with {retry_count} retries.")
            return
            
        print(f"⚠️ Attempt {retry_count} failed. Retrying...")

    print("❌ Mirroring failed after maximum retries.")

def main():
    # Check if the user provided the ISC path as an argument
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