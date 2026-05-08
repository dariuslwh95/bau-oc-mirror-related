
---

# OpenShift Mirror-to-Disk Automation

This repository provides the tooling and infrastructure required to mirror OpenShift Release images and Operators to a local disk (AWS EBS) and subsequently archive them in AWS S3. It is designed for air-gapped environment preparation using **oc-mirror v2**.

## 🏗️ Architecture Overview

The solution utilizes a RHEL 9 EC2 Instance (`t3.large`) equipped with a 4TB persistent EBS volume to handle the heavy I/O and storage requirements of the mirroring process.

* **Infrastructure:** Managed via Terraform (`/infra`).
* **Storage:** Dedicated XFS-formatted 4TB volume mounted at `/mnt/mirror-data`.
* **Security:** Locked-down Security Group (Outbound only) with IAM roles for SSM (Session Manager) and S3 administrative access.
* **Connectivity:** Uses an **S3 VPC Gateway Endpoint** to ensure 4TB transfers stay on the AWS private backbone for maximum speed and zero data egress costs.

## 📂 Directory Structure

```text
.
├── archive/            # Processed ISC YAMLs (historical record)
├── inbox/              # New ISC YAMLs waiting to be mirrored
├── infra/              # Terraform code (EC2, VPC, IAM, EBS)
├── scripts/
│   ├── init.sh         # User-data script (installs oc, oc-mirror, aws-cli)
│   ├── mirror-single.sh# Core script to process a single ISC from inbox
│   └── push-to-s3.sh   # Automation to sync local tarballs to S3
└── ref/                # Reference samples and metadata

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
2. Ensure your OpenShift Pull Secret is formatted as a valid JSON and placed at `~/.docker/config.json`.

### 3. Run a Mirror Task

Place your **ImageSetConfiguration (ISC)** YAML in the `inbox/` directory. It is highly recommended to use `screen` or `tmux` for long-running mirrors.

```bash
# Start a screen session
screen -S ocmirror

# Run the mirror for a specific ISC
./scripts/mirror-to-disk.sh inbox/imageset-4.20-operators-250426.yaml

```

## 🛠️ Script Logic

### `mirror-to-disk.sh`

This script performs the following logic to ensure data integrity:

* **Incremental Logic:** Uses `/mnt/mirror-data/metadata` to ensure subsequent runs for the same release (e.g., OCP 4.19) only download "diff" layers.
* **Tarball Finalization:** Locates all generated `mirror_seq*.tar` files, moves them to the output folder, and renames them with a timestamp.
* **Checksumming:** Generates `.sha256` fingerprints for every tarball for air-gap verification.

### `push-to-s3.sh`

Automates the transfer of finalized tarballs to S3:

```bash
aws s3 sync /mnt/mirror-data/output/ s3://your-mirror-bucket/ --exclude "*" --include "*.tar*"

```

## 📝 Key Considerations

* **OC-Mirror v2:** Optimized for v2, which utilizes a local registry service during the mirror process.
* **CPU Credits:** Monitor T3 instance CPU credits during 4-hour+ runs to avoid performance throttling.
* **Disk Space:** Periodically check usage on the 4TB volume: `df -h /mnt/mirror-data`.
* **IDMS/ITMS:** Cluster resources (ImageDigestMirrorSets) are generated within the working directory and bundled inside the `00001.tar` files.

## 🔒 Security

* **IAM Role:** The `oc-mirror-ssm-role` provides full S3 access without needing static keys.
* **Secrets:** **Never** commit your `pull-secret.json` or AWS credentials to this repository.
* **Networking:** The instance should reside in a private subnet using the S3 Gateway Endpoint.

## 🆘 Troubleshooting & Maintenance

If a process fails or the temporary directory becomes corrupted:

1. **Clean up corrupted temporary folders:**
```bash
# Replace [BASE_NAME] with your actual ISC name
rm -rf /mnt/mirror-data/output/*_tmp*

```


2. **Check Disk Space:**
```bash
df -h /mnt/mirror-data

```


3. **Resume Work:**
Always resume inside a `screen` session to prevent disconnects from killing the `oc-mirror` process.