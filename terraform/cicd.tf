# ==============================================================================
# CI/CD: GitHub Actions via OIDC, repositórios ECR e acesso de deploy (SCRUM-24)
# Projeto: ferry-telemetry-tde
#
# O GitHub Actions troca seu token OIDC por credenciais temporárias da role
# ferry-github-deploy: nenhuma chave AWS de longa duração fica no repositório.
# ==============================================================================

locals {
  ecr_repositories = toset([
    "ferry-central-ingestion",
    "ferry-central-worker",
    "ferry-central-dashboard",
    "ferry-nginx-central",
    "ferry-boat",
    "ferry-captain-panel",
    "ferry-nginx-edge",
  ])
}

# ------------------------------------------------------------------------------
# 1. Repositórios de imagens (Amazon ECR)
# ------------------------------------------------------------------------------

resource "aws_ecr_repository" "ferry" {
  for_each = local.ecr_repositories

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "ferry" {
  for_each   = aws_ecr_repository.ferry
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantem apenas as 20 imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

# ------------------------------------------------------------------------------
# 2. Provedor OIDC do GitHub e role assumida pelos workflows de deploy
# ------------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Somente workflows rodando na branch main deste repositório (suporta immutable subject do GitHub)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${split("/", var.github_repository)[0]}@*/${split("/", var.github_repository)[1]}@*:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "ferry-github-deploy-${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.github_assume_role.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for repository in aws_ecr_repository.ferry : repository.arn]
  }

  # Describe/Register de task definition não aceitam restrição por recurso
  statement {
    sid       = "EcsTaskDefinitions"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid     = "EcsServices"
    actions = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [
      aws_ecs_service.ferry_central_ingestion.id,
      aws_ecs_service.ferry_central_worker.id,
      aws_ecs_service.ferry_central_dashboard.id,
    ]
  }

  statement {
    sid     = "EcsMigrationsRunTask"
    actions = ["ecs:RunTask"]
    resources = [
      "arn:aws:ecs:${var.aws_region}:*:task-definition/ferry-central-ingestion-${var.environment}:*",
    ]
  }

  statement {
    sid       = "EcsTasksDescribe"
    actions   = ["ecs:DescribeTasks"]
    resources = ["arn:aws:ecs:${var.aws_region}:*:task/ferry-cluster-${var.environment}/*"]
  }

  statement {
    sid     = "PassEcsRoles"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution_role.arn,
      aws_iam_role.ecs_ingestion_task_role.arn,
      aws_iam_role.ecs_worker_task_role.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid     = "EdgeDeployCommand"
    actions = ["ssm:SendCommand"]
    resources = [
      aws_instance.ferry_barco.arn,
      "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
    ]
  }

  statement {
    sid       = "EdgeDeployStatus"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "ferry-github-deploy-policy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

# ------------------------------------------------------------------------------
# 3. Perfil da EC2 do Barco: SSM (deploy sem SSH) e leitura do ECR
# ------------------------------------------------------------------------------

resource "aws_iam_role" "barco_instance" {
  name = "ferry-barco-instance-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "barco_ssm" {
  role       = aws_iam_role.barco_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "barco_ecr_read" {
  role       = aws_iam_role.barco_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "barco" {
  name = "ferry-barco-instance-profile-${var.environment}"
  role = aws_iam_role.barco_instance.name
}
