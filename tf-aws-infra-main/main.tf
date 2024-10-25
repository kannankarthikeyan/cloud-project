provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(var.availability_zones, count.index)

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public_rt_association" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "private_rt_association" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.main_vpc.id
  name   = "app-security-group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "app-security-group"
  }
}
# DB Security Group
resource "aws_security_group" "db_sg" {
  name        = "database-security-group"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  tags = {
    Name = "database-sg"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "csye6225-db-subnet-group"
  description = "DB subnet group for RDS"
  subnet_ids  = aws_subnet.private_subnets[*].id

  tags = {
    Name = "csye6225-db-subnet-group"
  }
}

# DB Parameter Group
resource "aws_db_parameter_group" "db_parameter_group" {
  family = "postgres14"
  name   = "csye6225-db-parameter-group"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

# RDS Instance
resource "aws_db_instance" "db_instance" {
  identifier        = "csye6225"
  engine            = "postgres"
  engine_version    = "14"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "csye6225"
  username = "csye6225"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  parameter_group_name   = aws_db_parameter_group.db_parameter_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  skip_final_snapshot = true
  publicly_accessible = false

  tags = {
    Name = "csye6225-rds"
  }
}
resource "aws_instance" "web_app" {
  ami                         = var.custom_ami
  instance_type               = "t2.small"
  subnet_id                   = aws_subnet.public_subnets[0].id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "DB_NAME=csye6225" >> /opt/apps/webapp/.env
              echo "DB_USER=csye6225" >> /opt/apps/webapp/.env
              echo "DB_PASSWORD=${var.db_password}" >> /opt/apps/webapp/.env
              echo "DB_HOST=${aws_db_instance.db_instance.endpoint}" >> /opt/apps/webapp/.env
              echo "DB_PORT=5432" >> /opt/apps/webapp/.env
              
              sudo systemctl restart myapp
              EOF
  )

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  depends_on = [aws_security_group.app_sg, aws_db_instance.db_instance]

  tags = {
    Name = "web-app-instance"
  }
}
