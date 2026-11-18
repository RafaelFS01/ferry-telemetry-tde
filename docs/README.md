# Especificação Canônica de Arquitetura e Tecnologias — Ferry-Boat Salvador-Itaparica

**Status:** Aprovado e Homologado (Novembro/2026)  
**Projeto:** `ferry-telemetry-tde`  
**Escopo:** Definições tecnológicas de ponta a ponta, matriz de componentes, diretrizes de resiliência e resolução de decisões arquiteturais.

---

## 1. Diretrizes Gerais de Engenharia

O ecossistema foi calibrado para operar no **topo do ciclo de vida tecnológico (Cutting-Edge de Nov/2026)**, equilibrando inovação com estabilidade de produção:
* **Zero débito técnico:** Adoção de versões atuais e maduras de mercado (Node 24, Python 3.14, NestJS 12, Next.js 16, PostgreSQL 18, Terraform 1.17).
* **Paridade Dev/Prod (12-Factor App):** Mesma stack conteinerizada rodando em desenvolvimento local (`docker-compose.local.yml`) e nas tarefas gerenciadas serverless da nuvem AWS (**Amazon ECS / AWS Fargate**), com 1 instância EC2 dedicada para simulação de borda do Barco.
* **Eficiência Financeira e Auto-scaling Serverless:** Eliminação de instâncias EC2 ociosas na Central. A computação em terra opera sob demanda no AWS Fargate, escalando tarefas conforme a profundidade da fila de mensagens SQS ou métricas de CPU.
* **Resiliência Arquitetural Desacoplada (Sem Overengineering de Multi-AZ):** O banco de dados PostgreSQL opera em **Single-AZ com Point-in-Time Recovery (PITR)**. A alta disponibilidade e tolerância a falhas é garantida pela camada de software distribuído (Buffer FIFO offline no Barco e filas SQS na Central), eliminando a necessidade de replicação síncrona de hardware Multi-AZ (redução de 50% dos custos de banco).
* **Defesa em Profundidade (*Defense in Depth*) e Soberania Multi-Cloud:** O software não se acopla cegamente a recursos proprietários; proxies de borda (Nginx) garantem que a aplicação opere com idêntica segurança localmente, no porto (*On-Premises*) ou na nuvem.
* **Tolerância a Partições Severas (Teorema CAP / AP):** Mecanismos de buffer embarcado e mensageria pós-ingestão preparados para absorver até 24 horas ininterruptas de blackout de conectividade marítima sem contenção ou perda de dados.

---

## 2. Matriz Definitiva de Componentes (Novembro/2026)

| Camada / Módulo | Tecnologia | Versão Homologada | Papel Operacional |
| :--- | :--- | :--- | :--- |
| **Barco Computação** | **Instância AWS EC2** | **Ubuntu 24.04 LTS (`t3.micro`)** | Simulação realista do gateway IoT embarcado em alto-mar (ou execução local no Docker Compose). |
| **Barco (Edge Gateway)**| **Node.js Runtime** | **`node:24-alpine` (ou `26-alpine`)** | Runtime do coletor embarcado a bordo do ferry. |
| **Barco (Edge Gateway)**| **NestJS** | **`^12.0.x`** | Orquestrador do simulador GPS, keepalive, buffer FIFO e cliente gRPC. |
| **Central Computação** | **Amazon ECS / AWS Fargate** | **Serverless Tasks** | Execução elástica de contêineres sem gerenciamento de VMs ou sistema operacional. |
| **Central Telemetry** | **Python Runtime** | **`3.14-slim`** | Servidor gRPC assíncrono de alto desempenho e APIs internas. |
| **Central Telemetry** | **gRPC & Protobuf** | **`grpcio ^1.75.x` / `protobuf ^6.x`** | Ingestão RPC multiplexada via HTTP/2 e IDL canônico com mTLS. |
| **Central Telemetry** | **Driver BD** | **`asyncpg ^0.32.x`** | Driver assíncrono nativo de alta vazão para PostgreSQL 18. |
| **Central Telemetry** | **ORM & Migrations** | **SQLAlchemy `^2.0.4x` / Alembic `^1.15.x`** | Mapeamento relacional assíncrono, tipagem estrita (Mypy) e migrações nativas em Python. |
| **Database** | **PostgreSQL RDS** | **`postgres:18-alpine` (Single-AZ)** | Base relacional Single-AZ com Backups Automatizados no S3 e PITR (alta disponibilidade via SQS). |
| **Frontend Central** | **Next.js** | **`^16.0.x`** | Dashboard de supervisão marítima com Turbopack definitivo. |
| **Frontend Central** | **React** | **`^19.x`** | Interface reativa com Server Actions e hooks concorrentes. |
| **Frontend Central** | **TailwindCSS** | **`^4.0.x`** | Estilização compilada via motor Oxide em Rust (sem arquivos de config JS). |
| **Borda & Segurança** | **Nginx** | **`1.27-alpine`** | Proxy reverso conteinerizado, rate limiting, cabeçalhos de proteção e paridade dev/prod. |
| **Infraestrutura (IaC)**| **Terraform** | **`~> 1.17.0`** | Provisionamento 100% declarativo: VPC, Subnets, EC2 Barco, ECS Cluster, Tasks Fargate, ALB, RDS, SNS e SQS. |
| **CI/CD & Deploy** | **GitHub Actions + Amazon ECR**| **Workflows Automatizados** | Build multi-stage das imagens Docker, push para ECR e rolling updates contínuos no ECS Fargate. |

---

## 3. Justificativas Arquiteturais e Resolução de Decisões Críticas

### 3.1. Mensageria Desacoplada (SNS + SQS + Workers) vs. Persistência Síncrona
* **O Desafio da Partição Prolongada:** Em situações de enlace instável ou desligamento prolongado em alto-mar (por exemplo, 24 horas sem comunicação), a embarcação acumula mais de **17.280 pacotes** em seu buffer offline (considerando a coleta a cada 5s).
* **Mitigação do Efeito Manada (*Thundering Herd / Retry Storm*):**
  * Se o servidor gRPC fizesse a escrita diretamente no PostgreSQL de forma síncrona, a reconexão repentina de múltiplas embarcações geraria uma avalanche de milhares de transações simultâneas, esgotando o pool de conexões do banco e provocando estouro de deadlines (2.500 ms) no cliente.
  * Com **AWS SNS + SQS**: O servidor gRPC apenas valida o contrato Protobuf e publica a mensagem no broker em ~2 ms, confirmando o recebimento de volta para a embarcação e liberando imediatamente a conexão HTTP/2.
  * O **Worker consumidor (SQS)** drena a fila de forma controlada através de **escrita em lote (*batch processing*)** no PostgreSQL via `asyncpg`, absorvendo o *backpressure* sem sobrecarregar a base.
  * Mensagens malformatadas ou corrompidas caem na **Dead Letter Queue (DLQ)** após 3 tentativas, sem interromper o fluxo contínuo da telemetria.

### 3.2. Adoção do AWS Fargate Serverless (Eficiência Financeira e Zero Manutenção de SO)
* **Eliminação de Custos Ociosos:**
  * No modelo clássico com instâncias EC2, a equipe pagaria por servidores virtuais ligados 24/7, inclusive durante a madrugada quando o fluxo da travessia cessa.
  * Com o **AWS Fargate**, a cobrança ocorre estritamente por segundo de vCPU e memória alocados. Os workers de banco podem operar em escala mínima (0.25 vCPU / 0.5 GB RAM) ou escalar a zero, disparando novas tarefas apenas quando a métrica `ApproximateNumberOfMessagesVisible` da fila SQS indicar a chegada de dados.
* **Auto-Scaling Instantâneo sem Boot de VM:**
  * Quando a rajada de 17.000 mensagens represadas chega após uma partição de 24h, o ECS Fargate instancia múltiplos workers paralelos em questão de segundos, esvaziando a fila e desligando os nós extras imediatamente após a conclusão.
* **Segurança e Redução da Superfície de Ataque:**
  * O Fargate elimina a necessidade de abrir a porta SSH (22) na nuvem. Não há sistema operacional ou kernel Linux exposto para a equipe aplicar patches ou gerenciar chaves.
* **Unificação com Terraform e GitHub Actions:**
  * 100% dos recursos de nuvem (VPC, Cluster ECS, Task Definitions, Services, ALB, RDS) são provisionados declarativamente pelo **Terraform ~> 1.17.0**.
  * O deploy de novas versões é automatizado via **GitHub Actions** (build das imagens Docker, push no Amazon ECR e atualização das Task Definitions do Fargate), eliminando ferramentas concorrentes e scripts manuais em Bash/PowerShell.

### 3.3. Soberania e Defesa em Profundidade com Proxies Nginx Conteinerizados
* **Independência de Provedor (Anti-Lock-in):**
  * Confiar exclusivamente nas regras de borda do AWS ALB acoplaria a solução de forma irreversível à infraestrutura da AWS.
  * Ao manter contêineres Nginx dedicados de borda com políticas de rate limiting, compressão Gzip e injeção de headers de segurança (CSP, X-Frame-Options, HSTS), o sistema pode ser executado com idêntico nível de segurança tanto na nuvem AWS, quanto em servidores locais no terminal náutico (*On-Premises*) ou no Docker Compose de desenvolvimento.
* **Defesa em Profundidade:** Mesmo que o balanceador L7 externo receba o tráfego, o proxy reverso Nginx na borda do contêiner garante isolamento e proteção contra requisições que porventura contornem a malha externa.

### 3.4. Resiliência do Banco de Dados: Por que Single-AZ com PITR substitui o Multi-AZ?
* **O Diagnóstico de Overengineering do Multi-AZ:**
  * O Amazon RDS Multi-AZ provisiona duas instâncias completas em zonas distintas com replicação síncrona no nível de bloco de disco, **dobrando o custo total do banco de dados**.
  * Em sistemas distribuídos com **persistência desacoplada assíncrona**, a alta disponibilidade não precisa ser resolvida por replicação síncrona cara de hardware.
* **A Solução Adotada (Single-AZ + Backups S3 + PITR):**
  * O banco opera em uma única instância RDS PostgreSQL 18 em subnet privada, reduzindo o custo em 50%.
  * Ativam-se **Automated Backups com Point-in-Time Recovery (PITR)** com retenção de 7 dias, onde snapshots diários e logs de transação WAL contínuos são armazenados no **Amazon S3** (durabilidade de 99,999999999%).
  * **Comportamento em Falha:** Se a instância RDS reiniciar ou sofrer manutenção por 5 minutos, **nenhum dado de telemetria é perdido**: os pacotes ficam acumulados e protegidos na fila SQS ou no buffer do barco. Quando o banco volta a responder, os workers drenam a fila sem impacto operacional para a embarcação.

### 3.5. Eliminação Definitiva do Prisma no Python
* **Problema Resolvido:** O MVP utilizava `prisma-client-py`, que exigia a instalação forçada de Node.js, `package.json` e compilação de binários Rust dentro de contêineres do backend Python.
* **Solução:** Adoção de **SQLAlchemy 2.0 (assíncrono) + asyncpg** com **Alembic** para migrações relacionais.
* **Ganhos:** Elimina 100% das dependências de Node.js do backend Python, reduz pela metade a imagem Docker de produção e aumenta expressivamente a velocidade de inserção no PostgreSQL 18.

### 3.6. Desacoplamento do Frontend Cartográfico
* O frontend Next.js 16 não mais abrirá conexões TCP diretas com a porta 5432 do PostgreSQL em produção.
* A Central em Python 3.14 expõe uma API REST leve (`/api/telemetry/latest` e `/api/telemetry/history`) consumida pelos Server Components do Next.js, mantendo o banco de dados confinado estritamente na sub-rede privada da VPC.


---

### 3.6. Simulador Náutico e Evolução do Contrato (SCRUM-13)

O simulador do barco separa modelo físico puro e serviço NestJS. O serviço usa
relógio monotônico e publica `telemetry.generated` a cada 5000 ms, após aguardar
os listeners do EventEmitter. Sua operação não depende de gRPC nem de fila.
O evento em memória é consumido pelo buffer persistente da SCRUM-15.

Cada amostra possui `message_id` UUIDv4, alias local `packet_id` e sequência
incremental por execução. A sequência não reinicia entre viagens e não é
persistida após reinício do processo. O contrato mantém todos os campos existentes
e acrescenta `optional uint64 sequence_number = 8` em TelemetryPacket,
`optional double hdop = 6` e `optional uint32 satelites = 7` em NavigationData e
`optional double tensao_bateria_volts = 6` em PropulsionData. Valores int64/uint64
são strings no cliente TypeScript. Ausência dos campos opcionais identifica
mensagens legadas; `packet_id` não é um campo adicional de rede.

O percurso geodésico sintético liga São Joaquim (-12.9482, -38.5028) a Bom
Despacho (-12.9774, -38.5724), alternando ida e volta com atracação de 30s,
aceleração/frenagem de 0,1 m/s² e GPS com ruído limitado a 10m. Cruzeiro de
10–14 nós e 1500–1850 RPM; velocidade e RPM menores nas manobras. O modelo
inclui temperatura 78–92°C, 8–14 satélites, HDOP 0,8–2,0 e bateria 24–27V.
Tanque inicialmente cheio de 2000 L, consumo integrado e parada em emergência
ao esgotar o combustível, preservando a emissão de amostras.

Habilitação, tempo de atracação, capacidade e seed são configuráveis pelo ambiente
do barco. A seed reproduz sensores e não UUIDs. Passageiros e diagnósticos de rede
usam placeholders documentados no guia do barco. Rota, maré e motores são
sintéticos, sem calibração por embarcação real. A entrega não implementa fila
persistente, retransmissão, armazenamento dos novos campos na Central ou painéis.

### 3.7. Resiliência do Cliente gRPC (SCRUM-14)

O canal NestJS usa keepalive de 10000ms, timeout de 5000ms e
`keepalive_permit_without_calls=1`. A Central integrada permite pings sem dados
com intervalo de 10s. A política deve continuar compatível com proxies e
balanceadores do ambiente de implantação.

Cada tentativa de RPC recebe deadline novo de 2500ms (configurável para menos,
sem exceder esse teto). O cancelamento ocorre no transporte gRPC. Os status
`UNAVAILABLE` e `DEADLINE_EXCEEDED` acionam retries em bases 2/4/8/16/30s,
jitter de ±20% e teto absoluto de 30s. Há seis tentativas por padrão, incluindo
a original; `GRPC_RETRY_MAX_ATTEMPTS` aceita 1–10. Um único controlador de
retries evita sobreposição com a política nativa do canal.

O pacote mantém UUID, timestamp e sequência durante os reenvios. A primeira
falha transitória publica `telemetry.offline` imediatamente. O buffer
da SCRUM-15 persiste por UUID e aguarda `telemetry.delivery-settled`
antes de assumir a retransmissão. Apenas ACK aceito/duplicado do mesmo UUID
confirma entrega; rejeição, erro e cancelamento não autorizam remover a pendência.
Erros permanentes são propagados sem retry nem acionamento offline.

Eventos locais não substituem persistência. A SCRUM-14 não implementa a fila
nem conecta automaticamente o gerador ao cliente. Configuração e contrato
completo constam no README do `ferry-boat`.

### 3.8. FIFO Persistente e API Embarcada (SCRUM-15)

O armazenamento usa SQLite nativo do Node 24 em worker dedicado, com transações,
WAL e `synchronous=FULL`. Cada admissão só conclui após commit. O modo exclusivo
permite apenas um consumidor por arquivo e libera o bloqueio ao encerrar o
processo, inclusive após queda abrupta. Banco e WAL residem no volume local
persistente `boat-buffer`; arquivos corrompidos não são apagados automaticamente.

O banco mantém a ordem de entrada da coleta e o último pacote. A janela em RAM
é limitada a 5000 itens por padrão; o excedente é paginado do disco. Esse limite
não causa descarte nem limita a quantidade total de pacotes duráveis. A sequência
do simulador pode reiniciar por execução; a posição FIFO persistida não reinicia.

Uma única operação de envio controla a cabeça da fila. O buffer aguarda os
retries da SCRUM-14 e só remove após ACK aceito/duplicado do mesmo UUID, com
pausa mínima de 20ms entre confirmações e próximos envios. Se o ACK se perder
ou houver queda antes da remoção local, o mesmo UUID pode ser retransmitido;
a Central mantém a idempotência. Rejeições e erros permanentes bloqueiam a fila
sem pular itens. Falhas de disco são expostas como `storage_error`.

`GET /telemetry/buffer/status` retorna contadores de pendências, cache RAM,
excedente em disco e estado operacional. `GET /telemetry/latest` retorna a
última coleta persistida, ou 404 antes da primeira. Ambos usam `Cache-Control:
no-store`. Os valores int64/uint64 continuam strings. O evento local continua
em memória; a durabilidade se aplica às admissões confirmadas no SQLite.

## 4. Governança Ágil, Ferramentas e Rastreabilidade Integrada (Jira + GitHub)

Para assegurar controle rigoroso de prazos, alocação de responsabilidades e histórico auditável de cada decisão técnica, o projeto adota o framework ágil **Scrum** associado à esteira de desenvolvimento integrado **Jira Software + GitHub Cloud**:

### 4.1. Ferramental Oficial Homologado
1. **Jira Software Cloud:**
   - **Projeto:** `ferry-telemetry-tde` (Chave: `SCRUM`, Board ID: `1`)
   - **Espaço:** [rafafigolif.atlassian.net](https://rafafigolif.atlassian.net)
   - **Papel:** Gestão de backlog, épicos, planejamento de sprints, estimativas por Story Points, atribuição de responsáveis e acompanhamento do burndown chart.
2. **GitHub:**
   - **Repositório:** [https://github.com/RafaelFS01/ferry-telemetry-tde](https://github.com/RafaelFS01/ferry-telemetry-tde)
   - **Papel:** Versionamento Git, branches protegidas, revisão por pares (*Code Review*) e esteira de CI/CD.
3. **GitHub for Atlassian (Integração Oficial em Nuvem):**
   - **Conexão:** Organização GitHub `RafaelFS01` vinculada diretamente ao workspace Atlassian.
   - **Rastreabilidade Bidirecional:** A presença da chave da issue (ex: `SCRUM-6`) no nome da branch, mensagens de commit ou títulos de Pull Request atualiza dinamicamente o status no Jira, vinculando commits, deploys e revisões diretamente no card da tarefa.
4. **GitHub Actions:** Execução automatizada de linters, testes de compatibilidade gRPC/Protobuf e build de imagens Docker multi-stage.
5. **Docker Compose:** Paridade de execução local (`docker-compose.local.yml`).
6. **Terraform (~> 1.17):** Infraestrutura como Código (IaC) declarativa na AWS.

---

### 4.2. Calendário Oficial de Sprints (Novembro/2026)
O projeto desenvolve-se ao longo de **21 dias** divididos em **4 Sprints**, com entrega dos artefatos em **22/11/2026** e apresentação final no **Demo Day de 23/11/2026**:

| Sprint | Período | Foco Técnico Principal |
| :---: | :---: | :--- |
| **Sprint 1** | **02/11 a 06/11/2026** | **Fundação, Contratos IDL e Infraestrutura Base:** Contrato `proto/telemetry.proto` (`ferry.telemetry.v1`), Módulos Terraform de VPC, Subnets, RDS Postgres 18 e Cluster ECS, orquestração local Docker Compose, setup do nó Barco (NestJS 12 / Node 24) e servidor assíncrono Python grpc.aio. |
| **Sprint 2** | **07/11 a 12/11/2026** | **Comunicação gRPC Resiliente e Ingestão com Idempotência:** Simulador GPS náutico Salvador-Itaparica, cliente gRPC resiliente com deadlines e keepalive, buffer FIFO offline com persistência em disco e persistência assíncrona com Alembic/SQLAlchemy 2.0. |
| **Sprint 3** | **13/11 a 18/11/2026** | **Desacoplamento Assíncrono e Interfaces Web:** Módulos Terraform para SNS/SQS com DLQ, worker consumidor em lote, IaC Fargate/ALB, proxies Nginx, Painel do Capitão em Next.js 16 e Dashboard Náutico com Leaflet. |
| **Sprint 4** | **19/11 a 22/11/2026** | **CI/CD, Testes de Resiliência E2E e Homologação:** Pipeline GitHub Actions, suíte de testes Pytest/Jest, teste de partição de 24h (17.280 pacotes), deploy e validação E2E na AWS e runbooks operacionais. |
| **Demo Day** | **23/11/2026** | **Apresentação Final e Demonstração Prática:** Defesa do sistema distribuído e simulação ao vivo dos cenários de partição de rede. |

---

### 4.3. Padrão de Nomenclatura e Rastreabilidade Git

Para acionar a sincronização em tempo real do app **GitHub for Atlassian**, toda a equipe adota as seguintes regras estritas:

1. **Branches de Trabalho:**
   - Criadas exclusivamente a partir da branch `main` atualizada.
   - Padrão: `<tipo>/SCRUM-<ID>-<nome-kebab-case>`
   - Exemplos:
     - `feature/SCRUM-6-contrato-protobuf`
     - `feature/SCRUM-14-cliente-grpc-resiliente`
     - `docs/SCRUM-28-runbooks-apresentacao`
2. **Mensagens de Commit (Conventional Commits Rastreável):**
   - Formato: `<tipo>(SCRUM-<ID>): <descrição no imperativo em português>`
   - **Granularidade obrigatória nas branches:** Criar um commit por arquivo alterado ou por alteração lógica individual, sempre com descrição específica e referência ao ticket. Não reunir várias alterações independentes em um único commit genérico.
   - **Seleção das alterações:** Adicionar apenas o arquivo correspondente com `git add -- caminho/do/arquivo` e conferir `git diff --cached` antes de cada commit. Quando um arquivo contiver mudanças independentes, separar os trechos com `git add -p -- caminho/do/arquivo`. Repetir o processo para os demais arquivos ou alterações, evitando `git add .` quando houver mudanças independentes.
   - Exemplos:
     - `feat(SCRUM-6): define mensagens e rpc unaria no protobuf`
     - `feat(SCRUM-15): implementa buffer fifo e escrita periodica em disco`
     - `test(SCRUM-26): simula particao de rede de 24h sem perda de dados`
3. **Pull Requests:**
   - Título obrigatório: `[SCRUM-<ID>] <Título descritivo da entrega>`
   - O corpo do PR deve conter link direto para o card do Jira e descrição das alterações validadas.
   - Bloqueio de merge direto na `main` sem aprovação de code review e CI verde.
