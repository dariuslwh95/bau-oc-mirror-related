#!/bin/bash
# Variables injected by Terraform
MOUNT_PATH="${mount_path}"
BASE_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients"

# Logs for debugging (View via: cat /var/log/user-data.log)
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

set -e

echo "=== Starting OCP Mirror Node Setup ==="

This is a solid starting point, but we need to make it more robust for Nitro-based instances (like your t3.large), where device names can be unpredictable.

The following update handles the logic of finding the disk, formatting it (only if empty), and safely appending the UUID to /etc/fstab to ensure it persists across reboots.

Bash
# 1. Disk Management & Persistence
echo "Starting Disk Management..."

# Wait for the EBS volume to appear (Checking for common Nitro and Legacy names)
while [ ! -b /dev/sdh ] && [ ! -b /dev/nvme1n1 ]; do 
    echo "Waiting for EBS volume to attach..."
    sleep 5 
done

# Nitro instances use NVMe names. This finds the 4TB disk that isn't mounted.
# We exclude the root disk (usually nvme0n1) and find the first available block device.
DEVICE=$(lsblk -rno NAME,MOUNTPOINT,SIZE | awk '$2=="" && $3~/[3-4]T/ {print "/dev/"$1}' | head -n1)

if [ -z "$DEVICE" ]; then
    echo "❌ Error: Could not find an unmounted ~4TB device."
    exit 1
fi

# Format with XFS if no filesystem exists
if [ -z "$(lsblk -fno FSTYPE $DEVICE)" ]; then
    echo "Formatting $DEVICE with XFS..."
    sudo mkfs -t xfs $DEVICE
else
    echo "Filesystem already exists on $DEVICE, skipping format."
fi

# Create mount point and mount the device
sudo mkdir -p $MOUNT_PATH
sudo mount $DEVICE $MOUNT_PATH

# 2. Permanent Persistence via /etc/fstab
echo "Ensuring volume persists after reboot..."

# Get the UUID of the device
UUID=$(blkid -s UUID -o value $DEVICE)

# Backup fstab before modifying
sudo cp /etc/fstab /etc/fstab.bak

# Append to /etc/fstab if not already present
if ! grep -q "$UUID" /etc/fstab; then
    echo "Adding UUID=$UUID to /etc/fstab"
    # defaults,nofail ensures the system still boots if the disk is detached
    echo "UUID=$UUID  $MOUNT_PATH  xfs  defaults,nofail  0  2" | sudo tee -a /etc/fstab
    echo "✅ Persistence configured."
else
    echo "ℹ️ UUID already exists in /etc/fstab. Skipping."
fi

echo "EBS Volume mounted and persisted at $MOUNT_PATH"

# 2. Dependencies
echo "Installing base tools..."
# Added 'unzip' as it is required for AWS CLI installation
dnf install -y podman git tar unzip tmux

# 3. AWS CLI Installation
echo "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip ./aws

# 4. OpenShift Tooling
mkdir -p /tmp/ocp-tools
cd /tmp/ocp-tools

echo "Downloading oc and oc-mirror..."
curl -L -o oc-mirror.tar.gz "$BASE_URL/ocp/stable/oc-mirror.tar.gz"
curl -L -o oc.tar.gz "$BASE_URL/ocp/stable/openshift-client-linux.tar.gz"

tar -xzf oc-mirror.tar.gz
tar -xzf oc.tar.gz

chmod +x oc-mirror oc
sudo mv oc-mirror oc /usr/local/bin/

# 5. SSM Agent Check
echo "=== Ensuring SSM Agent is active ==="
if ! systemctl is-active --quiet amazon-ssm-agent; then
    echo "Installing SSM Agent..."
    dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
fi

echo "=== Installation Complete ==="
aws --version
oc version client
oc-mirror version --v2