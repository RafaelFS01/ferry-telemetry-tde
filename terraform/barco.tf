# ==============================================================================
# Instância EC2 Simuladora do Nó Barco (Edge Gateway IoT)
# Projeto: ferry-telemetry-tde | Módulo: Edge Computing (SCRUM-19)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Obtenção da AMI Oficial Ubuntu 24.04 LTS (Noble Numbat)
# ------------------------------------------------------------------------------

data "aws_ami" "ubuntu_noble" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# 2. Instância EC2 do Nó Barco (Subnet Pública com Acesso à Borda)
# ------------------------------------------------------------------------------

resource "aws_instance" "ferry_barco" {
  ami                         = var.ec2_barco_ami_id != "" ? var.ec2_barco_ami_id : data.aws_ami.ubuntu_noble.id
  instance_type               = var.ec2_barco_instance_type
  subnet_id                   = aws_subnet.ferry_public_subnet_b.id
  vpc_security_group_ids      = [aws_security_group.sg_ferry_barco.id]
  associate_public_ip_address = true
  key_name                    = var.ec2_barco_key_name != "" ? var.ec2_barco_key_name : null

  user_data                   = file("${path.module}/scripts/user_data_barco.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ec2_barco_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name        = "ferry-barco-root-volume"
      Component   = "Boat"
      Role        = "Edge-Simulator"
      Environment = var.environment
    }
  }

  tags = {
    Name        = "ferry-barco-simulator-${var.environment}"
    Component   = "Boat"
    Role        = "Edge-Simulator"
    Tier        = "Public"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 3. Elastic IP (IP Público Estático para o Simulador de Borda)
# ------------------------------------------------------------------------------

resource "aws_eip" "ferry_barco_eip" {
  domain = "vpc"

  tags = {
    Name        = "ferry-barco-eip-${var.environment}"
    Component   = "Boat"
    Role        = "Edge-Simulator"
    Environment = var.environment
  }
}

resource "aws_eip_association" "ferry_barco_eip_assoc" {
  instance_id   = aws_instance.ferry_barco.id
  allocation_id = aws_eip.ferry_barco_eip.id
}

