#!/bin/bash
# Variables injected by Terraform
MOUNT_PATH="${mount_path}"
BASE_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients"

# Logs for debugging (View via: cat /var/log/user-data.log)
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

set -e

echo "=== Starting OCP Mirror Node Setup ==="

# 1. Disk Management & Persistence
echo "Starting Disk Management..."

# Wait for the EBS volume to attach
# t3.large instances use NVMe, but we check both naming conventions for safety
while [ ! -b /dev/sdh ] && [ ! -b /dev/nvme1n1 ]; do 
    echo "Waiting for EBS volume to attach..."
    sleep 5 
done

# UPDATED: Nitro instances use NVMe names. 
# We look for the unmounted ~1TB device (adjusting the awk filter for 1T)
DEVICE=$(lsblk -rno NAME,MOUNTPOINT,SIZE | awk '$2=="" && $3~/[1]T/ {print "/dev/"$1}' | head -n1)

if [ -z "$DEVICE" ]; then
    echo "❌ Error: Could not find an unmounted ~1TB device."
    # Fallback: if awk fails, try the specific Nitro path for /dev/sdh
    if [ -b /dev/nvme1n1 ]; then DEVICE="/dev/nvme1n1"; else exit 1; fi
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
UUID=$(blkid -s UUID -o value $DEVICE)
sudo cp /etc/fstab /etc/fstab.bak

if ! grep -q "$UUID" /etc/fstab; then
    echo "Adding UUID=$UUID to /etc/fstab"
    echo "UUID=$UUID  $MOUNT_PATH  xfs  defaults,nofail  0  2" | sudo tee -a /etc/fstab
    echo "✅ Persistence configured."
fi

# 3. Dependencies & Python Installation
echo "Installing base tools and Python..."
# Added python3 and python3-pip for your automation needs
dnf install -y podman git tar unzip tmux tree python3 python3-pip

# 4. AWS CLI Installation
echo "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip ./aws

# 5. OpenShift Tooling
mkdir -p /tmp/ocp-tools
cd /tmp/ocp-tools

echo "Downloading oc and oc-mirror..."
curl -L -o oc-mirror.tar.gz "$BASE_URL/ocp/stable/oc-mirror.tar.gz"
curl -L -o oc.tar.gz "$BASE_URL/ocp/stable/openshift-client-linux.tar.gz"

tar -xzf oc-mirror.tar.gz
tar -xzf oc.tar.gz

chmod +x oc-mirror oc
sudo mv oc-mirror oc /usr/local/bin/

# 6. SSM Agent Check
echo "=== Ensuring SSM Agent is active ==="
if ! systemctl is-active --quiet amazon-ssm-agent; then
    dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
fi

# 7. OpenShift Pull Secret Setup
echo "=== Configuring OpenShift Pull Secret ==="

USER_HOME=$(eval echo ~$TARGET_USER)
ROOT_DOCKER_DIR="/root/.docker"
USER_DOCKER_DIR="$USER_HOME/.docker"

mkdir -p "$ROOT_DOCKER_DIR"
mkdir -p "$USER_DOCKER_DIR"

# Terraform substitutes ${pull_secret_contents} with raw text on deployment
cat << 'EOF' > /tmp/raw-pull-secret.txt
${pull_secret_contents}
EOF

# Process, compact, validate and apply permissions via jq
if jq -e . /tmp/raw-pull-secret.txt >/dev/null 2>&1; then
    jq -c . /tmp/raw-pull-secret.txt > "$ROOT_DOCKER_DIR/config.json"
    jq -c . /tmp/raw-pull-secret.txt > "$USER_DOCKER_DIR/config.json"
    
    chown -R "$TARGET_USER:$TARGET_USER" "$USER_DOCKER_DIR"
    chmod 600 "$ROOT_DOCKER_DIR/config.json" "$USER_DOCKER_DIR/config.json"
    
    rm -f /tmp/raw-pull-secret.txt
    echo "✅ Pull secret successfully written to root and $TARGET_USER environments."
else
    echo "❌ Error: The injected pull-secret text was not valid JSON."
    exit 1
fi

echo "=== Installation Complete ==="
python3 --version
aws --version
oc version client
oc-mirror version --v2