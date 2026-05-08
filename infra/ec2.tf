# 3. "Locked Down" Security Group
resource "aws_security_group" "ssm_only" {
  name        = "oc-mirror-ssm-only-sg"
  description = "No inbound access; Full outbound for setup"
  vpc_id      = aws_vpc.mirror_vpc.id 

  # No Inbound (ingress) rules
  
  # Allow ALL Outbound (Standard practice for worker nodes)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
  create_before_destroy = true
  }
}

# 4. Define the persistent EBS Volume (unchanged)
resource "aws_ebs_volume" "ocp_cache" {
  availability_zone = "ap-southeast-1a" # Ensure this matches your data source AZ
  size              = 4000
  type              = "gp3"
  
  lifecycle {
    prevent_destroy = true 
  }

  tags = { Name = "oc-mirror-persistent-cache" }
}

# 5. IAM Roles and Profiles (unchanged from your snippet)
resource "aws_iam_role" "ssm_role" {
  name = "oc-mirror-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "s3_full_access" {
  name = "oc-mirror-s3-full-access"
  role = aws_iam_role.ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          "*"
        ]
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "ssm_policy_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "oc-mirror-ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

data "aws_ami" "rhel_latest" {
  most_recent = true
  owners      = ["309956199498"] # Official Red Hat Owner ID

  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# 6. Updated EC2 Instance
resource "aws_instance" "mirror_worker" {
  ami           = data.aws_ami.rhel_latest.id
  instance_type = "t3.large"
  
  # --- CHANGE THIS LINE ---
  # Reference the resource defined in your vpc.tf
  subnet_id     = aws_subnet.public_subnet.id 
  # ------------------------

  # Ensure these also point to resources, not data sources
  vpc_security_group_ids = [aws_security_group.ssm_only.id]
  associate_public_ip_address = true # Required for the agent to use the Internet Gateway

  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name

  user_data = templatefile("../scripts/init.sh", {
    ebs_device = "/dev/sdh"
    mount_path = "/mnt/mirror-data"
  })

  tags = { Name = "oc-mirror-worker" }
}

# 7. Attach the Volume (unchanged)
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ocp_cache.id
  instance_id = aws_instance.mirror_worker.id
}