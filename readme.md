
---

# OpenShift Mirror-to-Disk Automation

This repository provides the tooling and infrastructure required to mirror OpenShift Release images and Operators to a local disk (AWS EBS) and subsequently archive them in AWS S3. It is designed for air-gapped environment preparation using **oc-mirror v2**.

## 🏗️ Architecture Overview

The solution utilizes a RHEL 9 EC2 Instance (`t3.xlarge`) equipped with a 1TB persistent EBS volume to handle the I/O and storage requirements of the mirroring process.

* **Infrastructure:** Managed via Terraform (`/infra`).
* **Storage:** Dedicated XFS-formatted 1TB volume mounted at `/mnt/mirror-data`.
* **Security:** Locked-down Security Group (Outbound only) with IAM roles for SSM (Session Manager) and S3 administrative access.
* **Connectivity:** Uses an **S3 VPC Gateway Endpoint** to ensure transfers stay on the AWS private backbone for maximum speed and zero data egress costs.
* **Mirroring Tool:** Uses **oc-mirror v1** to mirror OpenShift release images.

## 📂 Directory Structure

```text
.
├── inbox/              # New ISC YAMLs waiting to be mirrored
├── infra/              # Terraform code (EC2, VPC, IAM, EBS)
├── scripts/
│   ├── init.sh         # User-data script (installs oc, oc-mirror, aws-cli)
│   ├── main.py         # Core script to process a single ISC from inbox
│   └── multi.sh        # Wrapper script to process multiple ISCs in sequence
└── readme.md           # This file
```

## 🚀 Getting Started

### 1. Provision the Infrastructure

```bash
cd infra
terraform init
terraform apply
```

### 2. Prepare the Mirror Node

1. Connect to the instance via **AWS SSM (Session Manager)**.
2. Ensure your OpenShift Pull Secret is formatted as a valid JSON and placed at `infra/config.json`.

### 3. Run a Mirror Task

Place your **ImageSetConfiguration (ISC)** YAML in the `inbox/` directory.

*   **For a single mirror task:**
    ```bash
    # It is highly recommended to use screen or tmux for long-running mirrors
    tmux new -s ocmirror
    ./scripts/main.py ./inbox/imageset-4.20-operators-250426.yaml
    ```
*   **For multiple mirror tasks:**
    The `multi.sh` script can be used to run multiple mirror tasks in sequence.
    ```bash
    ./scripts/multi.sh
    ```

### 4. Upload Mirrored Content to S3

After successfully mirroring the content to the EBS volume, you can upload the generated `.tar` files to your pre-created S3 bucket. This makes them accessible for air-gapped environments or further distribution.

1.  **Upload Mirror Files to S3:**
    Use `aws s3 sync` to upload all `.tar` files from your mirror-data directories to your S3 bucket, excluding the temporary workspace.

    ```bash
    aws s3 sync /mnt/mirror-data/ s3://your-mirror-bucket/ --exclude "*/oc-mirror-workspace/*" --include "*.tar*" --acl public-read
    ```

    *   `/mnt/mirror-data/`: This is the source directory containing all your mirrored content, organized by ISC name.
    *   `s3://your-mirror-bucket/`: Replace this with the name of your S3 bucket.
    *   `--exclude "*/oc-mirror-workspace/*"`: This pattern ensures that the temporary `oc-mirror` workspace directories (which can be large and are not needed for distribution) are not uploaded.
    *   `--include "*.tar*"`: This ensures only the compressed mirror archives are uploaded.
    *   `--acl public-read`: Makes the uploaded objects publicly readable. Adjust as per your security requirements.

2.  **Accessing Uploaded Content:**
    Once uploaded, you can access your mirror content directly from S3.

    *   **Get Your S3 Bucket URL:**
        The URL format for S3 buckets is typically `https://<bucket-name>.s3.<region>.amazonaws.com/`. You can also find this in the AWS S3 console.

    *   **List All Object URLs:**
        To get a list of all uploaded `.tar` files and their S3 URLs, you can use the `aws s3 ls` command and construct the URLs.

        ```bash
        aws s3 ls s3://your-mirror-bucket/ --recursive | awk '{print "https://your-mirror-bucket.s3.ap-southeast-1.amazonaws.com/" $4}'
        ```
        Replace `your-mirror-bucket` and `<region>` with your actual bucket name and AWS region.


        aws s3api put-bucket-policy \
        --bucket `your-mirror-bucket`-ap-southeast-1-an \
        --policy '{
            "Version": "2012-10-17",
            "Statement": [
            {
                "Sid": "PublicReadGetObject",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::`your-mirror-bucket`/*"
            }
            ]
        }'

## Session Management (tmux)

For long-running mirror tasks, it is highly recommended to use a terminal multiplexer like `tmux` to prevent the process from being terminated due to a lost connection.

*   **Start a new named session:**
    ```bash
    tmux new -s ocmirror
    ```

*   **Detach from the session:**
    Press `Ctrl+b` then `d`.

*   **List running sessions:**
    ```bash
    tmux ls
    ```

*   **Attach to the last session:**
    ```bash
    tmux a
    ```
## changelog

*   **`config.json`:** Switched from `pull-secret.txt` to `config.json` in `infra/ec2.tf` to better align with oc-mirror standards.
*   **Permissions:** The `scripts/init.sh` script now uses Access Control Lists (ACLs) to grant both `ec2-user` and `ssm-user` read/write access to the `/mnt/mirror-data` directory, resolving potential permission issues during automated runs.


## 🛠️ Script Logic

### `main.py`

This script is the core of the mirroring process and is responsible for processing a single ImageSetConfiguration (ISC) file. Its main functions include:

*   **Dedicated Output Directory:** For each ISC, it creates a dedicated subdirectory within `/mnt/mirror-data` to store the mirrored images and metadata.
*   **`oc-mirror` Execution:** It calls the `oc-mirror --v1` command to perform the mirroring.
*   **Retry Logic:** It includes a retry mechanism to handle intermittent network issues.
*   **Checksum Generation:** After a successful mirroring, it generates an `md5sum` checksum for the resulting `.tar` files.

### `multi.sh`

This script is a simple wrapper that allows you to process all ImageSetConfiguration files in the `inbox/` directory in sequence. It calls `main.py` for each file.

## 📝 Key Considerations

* **CPU Credits:** Monitor T3 instance CPU credits during long runs to avoid performance throttling.
* **Disk Space:** Periodically check usage on the 1TB volume: `df -h /mnt/mirror-data`.
* **IDMS/ITMS:** Cluster resources (ImageDigestMirrorSets) are generated within the working directory and bundled inside the `mirror_seq*.tar` files.

## 🔒 Security

* **IAM Role:** The `oc-mirror-ssm-role` provides full S3 access without needing static keys.
* **Secrets:** **Never** commit your `config.json` or AWS credentials to this repository. The `infra/config.json` file is ignored by git.
* **Networking:** The instance should reside in a private subnet using the S3 Gateway Endpoint for interacting with S3.

## 🆘 Troubleshooting & Maintenance

If a process fails, you might need to clean up the output directory for that specific mirror run.

1.  **Clean up corrupted output folders:**
    ```bash
    # Replace [ISC_NAME] with the name of your imageset file (without .yaml)
    rm -rf /mnt/mirror-data/[ISC_NAME]
    ```

2.  **Check Disk Space:**
    ```bash
    df -h /mnt/mirror-data
    ```

3.  **Resume Work:**
    Always resume inside a `tmux` or `screen` session to prevent disconnects from killing the `oc-mirror` process.