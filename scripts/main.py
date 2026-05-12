import os
import re
import subprocess

STORAGE_PATH = "/mnt/mirror-data/gaia-operators"
imageset_config_path = "../inbox/"
CACHE_DIR = "/mnt/mirror-data/oc-mirror-cache"
MAX_RETRY_COUNT = 20


def is_tar_file_created():
    storage_path_contents = os.listdir(STORAGE_PATH)
    for content in storage_path_contents:
        if re.search(".tar$", content):
            return True
    return False

def run_mirroring():
    mirror_command=f"oc-mirror --v1 --config={imageset_config_path} file://{STORAGE_PATH}" --cache-dir={CACHE_DIR} --log-level=debug"
    print(f"Running mirror :{mirror_command}")
    for retry_count in range(MAX_RETRY_COUNT):
        print("Download attempt {}".format(retry_count))
        subprocess.run(mirror_command, shell = True, executable="/bin/bash")
        if is_tar_file_created():
            print(f"Mirroring completed with {retry_count} retries")
            return
    print("Mirroring failed")
    return

def main():
   run_mirroring()

if __name__ == "__main__":
    main()