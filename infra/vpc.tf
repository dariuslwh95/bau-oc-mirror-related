# 1. Create the Custom VPC
resource "aws_vpc" "mirror_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "oc-mirror-vpc" }
}

# 2. Create a Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.mirror_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true # Required for SSM to reach AWS APIs
  tags = { Name = "oc-mirror-public-subnet" }
}

# 3. Add an Internet Gateway (Required for the 'Public' part)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.mirror_vpc.id
  tags   = { Name = "oc-mirror-igw" }
}

# 4. Create a Route Table to allow internet traffic
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.mirror_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# 5. Associate the Subnet with the Route Table
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.mirror_vpc.id
  service_name = "com.amazonaws.ap-southeast-1.s3"
  vpc_endpoint_type = "Gateway"

  # Automatically associate with your public/private route tables
  route_table_ids = [aws_route_table.public_rt.id] 

  tags = { Name = "oc-mirror-s3-endpoint" }
}