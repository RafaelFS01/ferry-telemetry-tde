# CI/CD (SCRUM-24)

| Workflow | Gatilho | O que faz |
|---|---|---|
| `ci-quality.yml` | push em `main`/`feature/**`/`fix/**`/`docs/**` e PRs | buf lint/breaking, `compose config`, `nginx -t` nas duas bordas, typecheck e testes do barco, ruff + pytest da central, typecheck/teste/build dos dois frontends e build (sem push) das imagens de produção |
| `cd-central-deploy.yml` | push em `main` que altere a central ou o contrato; manual | build/push de `ferry-central-ingestion`, `ferry-central-worker`, `ferry-central-dashboard` e `ferry-nginx-central` no ECR, migrations Alembic via Fargate `run-task` e rollout nos serviços ECS com espera por estabilidade |
| `cd-edge-deploy.yml` | push em `main` que altere o barco, o painel ou o Nginx de borda; manual | build/push de `ferry-boat`, `ferry-captain-panel` e `ferry-nginx-edge` e rollout na EC2 do barco via SSM |

O worker só é publicado quando `ferry-central/src/worker/main.py` existir (SCRUM-17).

## Autenticação

Não há chaves AWS no GitHub. O workflow troca o token OIDC do GitHub pelo papel
`ferry-github-deploy-<env>` (`terraform/cicd.tf`), que só aceita execuções da branch `main`.
A EC2 do barco baixa as imagens com o próprio perfil de instância.

## Configuração (Settings → Secrets and variables → Actions → Variables)

| Variável | Origem | Obrigatória |
|---|---|---|
| `AWS_DEPLOY_ROLE_ARN` | `terraform output github_deploy_role_arn` | sim |
| `EDGE_INSTANCE_ID` | ID da instância `ferry-barco` (`terraform output`) | sim, para o deploy de borda |
| `AWS_REGION` | região do Terraform | não (padrão `us-east-1`) |
| `DEPLOY_ENVIRONMENT` | `var.environment` do Terraform | não (padrão `prod`) |

## Primeiro deploy

1. `terraform apply` cria ECR, provedor OIDC, papel de deploy e perfil da EC2.
2. Cadastre as variáveis acima no repositório.
3. Na EC2, crie `/opt/ferry-boat/.env` (`BOAT_ID`, caminhos mTLS) e coloque os certificados em `/opt/ferry-boat/certs`.
   O barco envia para `telemetry.rioswesley.com.br:50051` (SCRUM-29); defina `CENTRAL_GRPC_URL` no `.env` só para usar outro endereço.
4. Rode os workflows de CD manualmente (Actions → *Run workflow*) ou faça merge em `main`.

Depois do primeiro deploy, quem publica as revisões das task definitions é o pipeline.
Os serviços ECS ignoram `task_definition` (`lifecycle.ignore_changes`), então um
`terraform apply` posterior não volta a usar a revisão provisória.
