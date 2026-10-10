# AWS provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Security Group
resource "aws_security_group" "app_sg" {
  name        = "flask-express-sg"
  description = "Allow SSH, frontend and backend ports"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Express frontend
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Flask backend
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# EC2 instance with dynamic secret injection
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  security_groups = [aws_security_group.app_sg.name]

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y git python3-pip nodejs npm
    npm install -g pm2

    cd /home/ubuntu
    git clone https://github.com/chirayus20/Jenkins_CICD_Chirayu.git app

    # Dynamically inject credentials into backend .env
    cat << 'ENVFILE' > /home/ubuntu/app/backend/.env
    DB_USER=${var.db_user}
    DB_PASSWORD=${var.db_password}
    DB_CLUSTER=${var.db_cluster}
    DB_NAME=${var.db_name}
ENVFILE

    chown -R ubuntu:ubuntu /home/ubuntu/app
    chmod 600 /home/ubuntu/app/backend/.env

    # Configure and start Flask backend with PM2
    cd /home/ubuntu/app/backend
    pip3 install -r requirements.txt
    sudo -u ubuntu pm2 start app.py --name "flask-backend" --interpreter python3

    # Configure and start Express frontend with PM2
    cd /home/ubuntu/app/frontend
    npm install
    sudo -u ubuntu pm2 start server.js --name "express-frontend"

    # Save PM2 process list and configure startup persistence
    sudo -u ubuntu pm2 save
    env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu
  EOF

  tags = {
    Name = "Flask-Express-Server"
  }
}
