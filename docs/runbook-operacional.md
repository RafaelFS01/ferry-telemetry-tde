# Runbook Operacional: Como Cumprir Pré-requisitos, Subir, Validar e Desligar o Ecossistema em Nuvem (AWS)

Este runbook consolida os procedimentos operacionais de ponta a ponta para inicialização, validação de integridade e encerramento de todos os componentes do sistema distribuído **Ferry-Boat Salvador-Itaparica** em nuvem (**AWS de Produção**).

Ele ensina detalhadamente **como instalar e configurar os pré-requisitos essenciais**, como subir toda a infraestrutura na nuvem (**AWS via Terraform e GitHub Actions**) e como acessar os serviços **tanto pelo DNS canônico nativo da AWS (sem precisar de domínio registrado)** quanto por **domínios customizados (Route 53)**.

---

## 1. Guia Passo a Passo: Pré-requisitos Mínimos

Como a aplicação é 100% conteinerizada e gerenciada por Infraestrutura como Código (Terraform) e esteiras de automação de CI/CD (GitHub Actions), **você NÃO precisa instalar Docker, Node.js ou Python no seu computador local**.

Você só precisa de três ferramentas simples instaladas no seu terminal:

---

### 1.1. Passo 1: Clonar o Repositório Corretamente (Submódulos Git)

Este projeto é modular e utiliza **Git Submodules** para os serviços da Central (`ferry-central`) e do Barco (`ferry-boat`).

Para clonar o projeto garantindo que todos os códigos-fonte sejam baixados:

```bash
# Clone recursivo (baixa o projeto principal e todos os submódulos de uma vez)
git clone --recursive https://github.com/RafaelFS01/ferry-telemetry-tde.git
cd ferry-telemetry-tde
```

> [!TIP]
> Se você já clonou o repositório com o `git clone` normal e as pastas `ferry-central` ou `ferry-boat` estiverem vazias, basta rodar dentro da pasta do projeto:
> ```bash
> git submodule update --init --recursive
> ```

---

### 1.2. Passo 2: Instalação e Configuração da AWS CLI v2

A AWS CLI permite que seus scripts e o Terraform se comuniquem com a nuvem AWS para criar e gerenciar recursos.

#### Instalação:
* **No Windows (via PowerShell ou Terminal como Administrador):**
  ```powershell
  winget install Amazon.AWSCLI
  ```
  *Ou baixe e execute o instalador oficial:* [AWSCLIV2.msi](https://awscli.amazonaws.com/AWSCLIV2.msi).
* **No Linux (Ubuntu/Debian):**
  ```bash
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip && sudo ./aws/install
  ```
* **No macOS:**
  ```bash
  curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
  sudo installer -pkg AWSCLIV2.pkg -target /
  ```

#### Obter Credenciais na AWS (Access Key):
1. Faça login no Console da AWS ([https://console.aws.amazon.com](https://console.aws.amazon.com)).
2. Na barra de busca superior, digite **IAM** e acerte em **Users (Usuários)**.
3. Clique no seu usuário (com permissão de Administrador / `AdministratorAccess`).
4. Acesse a aba **Security credentials (Credenciais de segurança)**.
5. Na seção **Access keys**, clique em **Create access key (Criar chave de acesso)**.
6. Selecione a opção **Command Line Interface (CLI)**, marque a caixa de confirmação e clique em **Next**.
7. Copie o **Access Key ID** e o **Secret Access Key** (ou baixe o arquivo `.csv`).

#### Configurar a AWS CLI no Terminal:
No terminal da sua máquina, execute:
```bash
aws configure
```
Preencha os dados solicitados:
* **AWS Access Key ID:** cole sua chave de acesso (ex.: `AKIAIOSFODNN7EXAMPLE`)
* **AWS Secret Access Key:** cole sua chave secreta (ex.: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)
* **Default region name:** `us-east-1` *(obrigatório, região homologada do projeto)*
* **Default output format:** `json`

#### Validar a Autenticação:
```bash
aws sts get-caller-identity
```
*Se retornar seu `UserId`, `Account` e `Arn`, sua AWS CLI está 100% pronta para uso.*

---

### 1.3. Passo 3: Instalação do Terraform (~> 1.17)

O Terraform é o motor de Infraestrutura como Código (IaC) que lê os arquivos da pasta `terraform/` e cria automaticamente todos os servidores, redes, bancos e balanceadores na nuvem.

#### Instalação:
* **No Windows (via PowerShell):**
  ```powershell
  winget install HashiCorp.Terraform
  ```
  *Ou baixe o binário:* [Terraform Downloads](https://developer.hashicorp.com/terraform/install), descompacte o `terraform.exe` e adicione a pasta à variável de ambiente `PATH`.
* **No Linux / macOS (via Homebrew ou pacote oficial):**
  ```bash
  brew install terraform
  ```

#### Validação:
```bash
terraform version
```
*Deve exibir `Terraform v1.17.x` (ou superior compatível).*

---

## 2. Executando em Nuvem (AWS de Produção)

Entenda o fluxo sequencial de subida da nuvem:
1. **Passo 1 (2.1 — Infraestrutura):** O Terraform provisiona todos os recursos de hardware virtual (VPC, Subnets, ALB, SQS, SNS, RDS PostgreSQL, Cluster ECS e EC2).
2. **Passo 2 (2.2 — Configurar Variáveis no GitHub):** Imediatamente após o `terraform apply`, copiar as variáveis exibidas no resumo do terminal (`EDGE_INSTANCE_ID` e `AWS_DEPLOY_ROLE_ARN`) para o GitHub Actions.
3. **Passo 3 (2.3 — Deploy da Aplicação e Banco):** O GitHub Actions compila os contêineres Docker, executa as migrações no RDS (Alembic) e atualiza os serviços.
4. **Passo 4 (2.4 — Injetar Certificados mTLS no Barco):** Executar o script automatizado de 1 comando para transferir os certificados criptográficos da CA para o simulador do Barco.
5. **Passo 5 (2.5 — Acesso e Teste):** Acessar os painéis web diretamente pelo navegador e testar a telemetria ao vivo.
6. **Passo 6 (2.6 — Validações Opcionais):** Testes de fumaça, fila SQS e validação de segurança do mTLS estrito.
7. **Passo 7 (2.7 — Teardown):** Destruição completa (`terraform destroy`) ou congelamento temporário de custos.

---

### 2.1. Passo 1: Criar a Infraestrutura Declarativa via Terraform

Com a AWS CLI autenticada e o Terraform instalado:

```powershell
cd terraform

# 1. Inicializa os plugins da AWS e TLS
terraform init

# 2. Planeja e valida as mudanças
terraform plan -out tfplan.binary

# 3. Provisiona toda a malha na nuvem AWS (demora de 8 a 12 minutos)
terraform apply tfplan.binary
# (Ou execute diretamente: terraform apply)
```

> [!NOTE]
> **Atenção para quem fez Fork do Repositório (Conta Nova do GitHub):**  
> A política de segurança IAM OIDC autoriza a esteira de CI/CD apenas para o repositório cadastrado na variável `github_repository` (por padrão: `RafaelFS01/ferry-telemetry-tde`).  
> Se você clonou um **fork próprio** (ex.: `seu-usuario/ferry-telemetry-tde`):
> 1. Crie o arquivo `terraform/terraform.tfvars`:
>    ```powershell
>    Copy-Item terraform.tfvars.example terraform.tfvars
>    ```
> 2. Adicione a linha abaixo no `terraform.tfvars`:
>    ```hcl
>    github_repository = "seu-usuario/ferry-telemetry-tde"
>    ```
> *(Se você estiver executando com o repositório original `RafaelFS01/ferry-telemetry-tde`, nenhuma alteração é necessária).*

> **O que acabou de ser criado?**  
> Todos os recursos de hardware virtual (VPC, Subnets, ALB, SQS, SNS, RDS PostgreSQL, Cluster ECS e EC2).  
> **Atenção:** O banco RDS foi criado, mas ainda está *vazio* (sem tabelas), e os contêineres Fargate precisam das imagens Docker do sistema para começar a operar.

---

### 2.2. Passo 2: Configurar as Variáveis no GitHub Actions (Imediato após o Terraform Apply)

> [!IMPORTANT]
> **ATENÇÃO CRÍTICA — NÃO PULE ESTE PASSO ANTES DE DISPARAR O DEPLOY!**  
> O Terraform acabou de imprimir um bloco formatado no **final absoluto do terminal**. Você precisa copiar esses valores para o GitHub Actions **antes** de rodar os workflows de deploy do Passo 3. Se você pular este passo, o workflow do Barco falhará com `AccessDeniedException`.

Ao final da execução do `terraform apply`, você verá na tela:

```text
z_resumo_operacional_deploy = <<EOT

================================================================================
>>> ATENÇÃO: COPIE AS VARIÁVEIS ABAIXO PARA O GITHUB ACTIONS <<<
Repositório: Settings -> Secrets and variables -> Actions -> Variables
URL Direta : https://github.com/RafaelFS01/ferry-telemetry-tde/settings/variables/actions

EDGE_INSTANCE_ID     : i-0f4b8fd8012f1d880
AWS_DEPLOY_ROLE_ARN  : arn:aws:iam::782747473447:role/ferry-github-deploy-prod
ALB_DNS_NAME         : ferry-alb-prod-1350117301.us-east-1.elb.amazonaws.com
EC2_BARCO_PUBLIC_IP  : 18.207.236.138
================================================================================

EOT
```

#### O que é cada variável e para que serve?

1. **`EDGE_INSTANCE_ID` (Obrigatória sempre que recriar a infraestrutura):**
   * **O que é:** O identificador físico único da máquina virtual EC2 que simula o Barco (ex.: `i-0f4b8fd8012f1d880`).
   * **Por que precisa configurar:** Toda vez que o Terraform cria uma máquina EC2, a AWS gera um ID físico novo. A esteira de CI/CD `CD Edge (EC2 Barco)` usa esse ID para enviar o comando de deploy via AWS SSM. A política de segurança IAM da AWS adota o princípio de menor privilégio (*least privilege*) e autoriza o comando **estritamente para o ARN da máquina atual**. Se a variável no GitHub estiver vazia ou apontando para um ID antigo, a esteira falha imediatamente com `AccessDeniedException`.

2. **`AWS_DEPLOY_ROLE_ARN` (Obrigatória apenas na primeira vez / conta nova):**
   * **O que é:** O ARN do papel IAM criado pelo Terraform para permitir que o GitHub Actions se autentique na AWS via OIDC (OpenID Connect), sem senhas nem chaves de acesso estáticas no repositório.
   * **Por que precisa configurar:** Se você estiver implantando o projeto pela primeira vez na sua própria conta AWS (ou num repositório clonado/fork), o GitHub Actions precisa desse ARN para saber qual papel assumir (`sts:AssumeRoleWithWebIdentity`). Se você já cadastrou essa variável antes no seu repositório, não precisa mexer nela.

#### Como cadastrar no GitHub (Passo a Passo):

1. Acesse o seu repositório no GitHub.
2. Vá em **Settings** > **Secrets and variables** > **Actions** > aba **Variables** (ou clique no link direto exibido no final do seu terminal).
3. **Se for a primeira vez que você roda na sua conta:**
   * Clique em **New repository variable**.
   * Nome: `AWS_DEPLOY_ROLE_ARN`
   * Valor: copie o ARN exibido no terminal (ex.: `arn:aws:iam::123456789012:role/ferry-github-deploy-prod`).
   * Clique em **Add variable**.
4. **Cadastre ou atualize a `EDGE_INSTANCE_ID`:**
   * Se a variável ainda não existir: clique em **New repository variable**, nome `EDGE_INSTANCE_ID` e cole o ID (ex.: `i-0f4b8fd8012f1d880`).
   * Se a variável já existir: clique no ícone de lápis ✏️ ao lado de `EDGE_INSTANCE_ID`, cole o novo ID e clique em **Save**.

---

### 2.3. Passo 3: Fazer o Deploy da Aplicação e do Banco de Dados via GitHub Actions

Agora que as variáveis estão configuradas no GitHub, você pode disparar o deploy 100% automático das aplicações e criar as tabelas no banco RDS.

**Você NÃO precisa alterar nenhum arquivo nem criar commits desnecessários.**

Como os workflows possuem o gatilho `workflow_dispatch`, você pode disparar o deploy a qualquer momento:

* **Opção 1 (Pelo Navegador no GitHub — Mais Simples):**
  1. Acesse o seu repositório no GitHub e clique na aba **Actions**.
  2. Na lista à esquerda, clique em **CD Central (ECS)**.
  3. À direita, clique no botão cinza **Run workflow**, selecione a branch `main` e confirme em **Run workflow**.
  4. Na sequência, clique em **CD Edge (EC2 Barco)**.
  5. À direita, clique no botão cinza **Run workflow**, selecione a branch `main` e confirme em **Run workflow**.
  6. As esteiras do GitHub Actions farão todo o trabalho sozinhas em ~5 minutos:
     * Constroem as imagens Docker e as enviam para o Amazon ECR.
     * Executam as migrações do banco (Alembic) criando a tabela `telemetria` no RDS.
     * Atualizam os serviços do ECS Fargate e inicializam a aplicação do Barco na EC2 via SSM.

* **Opção 2 (Direto pelo Terminal via GitHub CLI):**
  Se preferir fazer sem sair do terminal, basta rodar:
  ```powershell
  gh workflow run "CD Central (ECS)" --ref main
  gh workflow run "CD Edge (EC2 Barco)" --ref main
  ```

*(No dia a dia de desenvolvimento, qualquer `git push origin main` que altere código real em `ferry-central/` ou `ferry-boat/` já dispara esse deploy automaticamente sem você precisar clicar em nada).*

> Ao concluir o deploy das esteiras, siga diretamente para o **Passo 4 (Seção 2.4 — Injetar Certificados mTLS no Barco)**!

---

### 2.4. Passo 4: Injetar os Certificados mTLS no Barco (Script Automatizado)

A embarcação opera em produção com **mTLS estrito**. O contêiner `ferry-boat` (NestJS) exige os certificados criptográficos assinados pela CA (`ca.crt`, `boat.crt`, `boat.key`) para validar o aperto de mão gRPC com o ALB na porta `50051`.

Sem esses certificados, o contêiner do Barco não consegue se conectar à nuvem e o status fica em erro.

Para injetar os certificados e o `.env` na EC2 em apenas 5 segundos (sem precisar de chaves SSH nem comandos manuais), execute o script pronto na raiz do projeto:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-edge-certs.ps1
```

#### O que esse script faz automaticamente:
1. Extrai `ca.crt`, `boat.crt`, `boat.key` e o DNS do ALB direto do estado do Terraform.
2. Codifica em Base64 preservando as quebras de linha exatas do padrão RFC PEM.
3. Transmite os arquivos via AWS SSM diretamente para `/opt/ferry-boat/certs/` na máquina EC2.
4. Ajusta a propriedade (`chown -R 1000:1000`) e permissões (`chmod 644`) para o usuário não-root `node` do contêiner.
5. Gera o arquivo `/opt/ferry-boat/.env` configurando a conexão gRPC no ALB (`CENTRAL_GRPC_URL=${alb_dns}:50051`).
6. Reinicia o serviço `ferry-boat` e valida o endpoint de saúde `http://<IP_DA_EC2>/api/edge/health`, exibindo na tela:

```text
[✓] SUCESSO: O Barco esta online, autenticado via mTLS e operando normalmente!
- Painel do Capitao: http://<IP_DO_BARCO>/
- Central Dashboard: http://<ALB_DNS>/
```

---

### 2.5. Passo 5: Como Acessar os Recursos (URLs e Endpoints)

Agora que a infraestrutura e a aplicação estão ativas, consulte os links gerados para acessar os painéis:

> [!IMPORTANT]
> **Você NÃO precisa ter um domínio próprio registrado para acessar e testar o sistema.**
> Toda a infraestrutura é acessível imediatamente através do **DNS nativo do Load Balancer da AWS** e do **IP público da EC2 do Barco**.

#### A. Acesso Padrão (Usando o DNS Nativo da AWS — Sem Domínio)

Para descobrir os endereços gerados pela AWS na sua conta, execute:
```bash
# Obtém o DNS público do Application Load Balancer
terraform -chdir=terraform output -raw alb_dns_name

# Obtém o IP público da EC2 que simula o Barco
terraform -chdir=terraform output -raw boat_public_ip
```

Com esses valores, acesse os serviços por qualquer navegador ou terminal:

| Recurso | URL Canônica Nativa da AWS | Descrição |
| :--- | :--- | :--- |
| **Dashboard Náutico Central** | `http://<ALB_DNS_NAME>/` | Interface web em Next.js 16 com Leaflet.js exibindo as balsas ao vivo. |
| **API REST da Central** | `http://<ALB_DNS_NAME>/api/telemetry/latest` | Endpoint FastAPI que consulta o banco RDS e retorna o JSON da telemetria. |
| **Healthcheck da Ingestão** | `http://<ALB_DNS_NAME>/health` | Verifica a integridade da ingestão na nuvem. |
| **Painel do Capitão (Barco)** | `http://<BOAT_PUBLIC_IP>/` | Painel web de bordo da embarcação simulada na EC2 (porta 80 via Nginx). |
| **API de Borda do Barco** | `http://<BOAT_PUBLIC_IP>/api/edge/telemetry/buffer/status` | Exibe o estado da fila FIFO e do buffer SQLite no barco. |
| **Canal gRPC de Telemetria** | `<ALB_DNS_NAME>:50051` | Porta gRPC HTTP/2 protegida por mTLS estrito. |

---

#### B. Configuração Opcional: Usando Domínios Customizados (Route 53 — SCRUM-29)

Se você ou sua equipe possuírem um domínio registrado (por exemplo, `rioswesley.com.br` no Registro.br), o projeto possui integração nativa com o **Amazon Route 53** (`terraform/dns.tf`):

* **Como delegar no Registro.br:**  
  Consulte os nameservers gerados pelo Terraform:
  ```bash
  terraform -chdir=terraform output route53_name_servers
  ```
  No painel do Registro.br, altere os servidores DNS para os 4 nameservers retornados.
* **Endpoints amigáveis disponíveis após a delegação:**
  | Subdomínio | Destino | Protocolo |
  | :--- | :--- | :--- |
  | `https://painel.rioswesley.com.br/` | Central Dashboard | HTTPS (:443 com certificado público ACM) |
  | `https://capitao.rioswesley.com.br/` | Painel do Capitão | HTTPS (:443 via ALB com HTTP 301 redirect para a EC2) |
  | `telemetry.rioswesley.com.br:50051` | Ingestão gRPC | HTTP/2 mTLS com a CA do projeto |

*(Para detalhes da sequência de validação do certificado público ACM, consulte [docs/dns.md](file:///c:/Users/rafa_/Cursor/ferry-telemetry-tde/docs/dns.md)).*

---

### 2.6. Passo 6: (Opcional) Testes de Fumaça (Smoke Tests) e Validação de Segurança

> **Este passo é opcional.** O sistema já está 100% operacional no Passo 2.5. Execute os testes abaixo apenas se desejar auditar a saúde das tarefas Fargate e provar que a segurança do mTLS estrito está bloqueando conexões não autorizadas.

Execute estes testes rápidos para validar que a nuvem está 100% saudável:

#### 1. Verificar Saúde dos Contêineres no ALB
```bash
aws elbv2 describe-target-health --target-group-arn $(terraform -chdir=terraform output -raw alb_grpc_target_group_arn)
aws elbv2 describe-target-health --target-group-arn $(terraform -chdir=terraform output -raw alb_dashboard_target_group_arn)
```
*Ambos devem retornar `TargetHealth.State = "healthy"`.*

#### 2. Prova Prática do mTLS Estrito na Porta 50051
* **Teste SEM certificado de cliente (A nuvem DEVE recusar o acesso):**
  ```bash
  ALB_DNS=$(terraform -chdir=terraform output -raw alb_dns_name)
  curl -vk --http2 https://${ALB_DNS}:50051
  ```
  *Resultado esperado:* Falha de aperto de mão TLS (`SSL_ERROR_BAD_CERT_ALERT` ou `handshake failure`), provando que conexões não autorizadas são bloqueadas na borda.
* **Teste COM o certificado emitido pela CA do barco (A nuvem DEVE aceitar):**
  ```bash
  curl -vk --http2 \
    --cacert terraform/certs/ca.crt \
    --cert terraform/certs/boat.crt \
    --key terraform/certs/boat.key \
    https://${ALB_DNS}:50051
  ```
  *Resultado esperado:* Handshake TLS concluído com sucesso via HTTP/2 ALPN.

#### 3. Verificar Fila SQS e CloudWatch
```bash
aws sqs get-queue-attributes \
  --queue-url $(terraform -chdir=terraform output -raw sqs_db_writer_queue_url) \
  --attribute-names ApproximateNumberOfMessages
```
*Em regime normal, o total de mensagens deve oscilar entre 0 e 10 (consumo contínuo pelos workers).*

---

### 2.7. Passo 7: Ao Terminar: Teardown Seguro e Congelamento de Custos

> [!WARNING]
> **NÃO execute esta seção enquanto estiver usando ou demonstrando o sistema.**  
> Execute estes comandos apenas **quando terminar de usar, testar ou apresentar o projeto**, para desligar as máquinas virtuais e pausar o banco, evitando custos desnecessários na sua conta da AWS.

Quando terminar os testes ou apresentações, use estes comandos para evitar cobranças indesejadas na AWS:

#### Parada Temporária (Congelamento sem perder nada):
```bash
# 1. Zera as tarefas do ECS Fargate
aws ecs update-service --cluster ferry-cluster-prod --service ferry-central-ingestion-prod --desired-count 0
aws ecs update-service --cluster ferry-cluster-prod --service ferry-central-worker-prod --desired-count 0
aws ecs update-service --cluster ferry-cluster-prod --service ferry-central-dashboard-prod --desired-count 0

# 2. Desliga a EC2 do Barco
BOAT_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=ferry-boat-prod" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ec2 stop-instances --instance-ids "$BOAT_ID"

# 3. Pausa a instância do RDS PostgreSQL temporariamente
aws rds stop-db-instance --db-instance-identifier ferry-postgres-central
```

#### Destruição Completa via Terraform (Remove 100% dos recursos):
```bash
cd terraform
terraform destroy -auto-approve
```
