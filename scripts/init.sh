#!/bin/bash
# Variables injected by Terraform
MOUNT_PATH="${mount_path}"
BASE_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients"

# Logs for debugging (View via: cat /var/log/user-data.log)
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

set -e

echo "=== Starting OCP Mirror Node Setup ==="

# 1. Disk Management
while [ ! -b /dev/sdh ] && [ ! -b /dev/nvme1n1 ]; do 
    echo "Waiting for EBS volume to attach..."
    sleep 5 
done

# Nitro instances use NVMe names. This finds the non-root disk.
DEVICE=$(lsblk -rno NAME,MOUNTPOINT | awk '$2=="" {print "/dev/"$1}' | grep -v "nvme0n1" | head -n1)

if [ -z "$(lsblk -fno FSTYPE $DEVICE)" ]; then
    echo "Formatting $DEVICE with XFS..."
    mkfs -t xfs $DEVICE
fi

mkdir -p $MOUNT_PATH
mount $DEVICE $MOUNT_PATH
echo "EBS Volume mounted at $MOUNT_PATH"

# 2. Dependencies
echo "Installing base tools..."
# Added 'unzip' as it is required for AWS CLI installation
dnf install -y podman git tar unzip

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