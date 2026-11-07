# ==============================================================================
# Amazon RDS PostgreSQL 18 (Arquitetura Single-AZ com PITR e Backups S3)
# Projeto: ferry-telemetry-tde | Módulo: Relational Database (SCRUM-8)
# ==============================================================================

resource "aws_db_instance" "ferry_postgres" {
  identifier = "ferry-postgres-central"

  # Engine e Computação
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Armazenamento e Criptografia
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Credenciais e Dados Iniciais
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Topologia Single-AZ (Redução de 50% de custo justificada por resiliência via SQS e Buffer Edge)
  multi_az = false

  # Rede e Isolamento Perimetral
  db_subnet_group_name   = aws_db_subnet_group.ferry_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.sg_ferry_rds.id]
  publicly_accessible    = false

  # Políticas de Backup e Point-in-Time Recovery (PITR)
  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:30-Sun:05:30"
  copy_tags_to_snapshot   = true

  # Upgrades e Ciclo de Vida
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  skip_final_snapshot         = true
  deletion_protection         = false

  tags = {
    Name      = "ferry-postgres-central"
    Tier      = "Private-DB"
    Component = "Database"
  }
}

