# Engenharia do Caos e Teste de Carga até a Saturação (AWS)

Este guia documenta os ensaios práticos realizados diretamente na infraestrutura AWS (`us-east-1`), bem como o roteiro reproduzível para simulação ao vivo durante a apresentação (**Critérios C2, C3 e Seção 5 — Testes de Bancada #1 e #2**).

Script gerador utilizado: [`scripts/chaos_load_test.py`](../scripts/chaos_load_test.py).

---

## 1. Cenário 1 — Teste de Carga em Rampa até o Ponto de Quebra + Auto Scaling ECS (`C2`)

### 1.1. Como reproduzir ao vivo
Com a infraestrutura Terraform aplicada e o ambiente Python local com `grpcio`/`protobuf` (`ferry-central/.venv`):

```powershell
.\ferry-central\.venv\Scripts\python.exe scripts/chaos_load_test.py `
  --stages 50:20,150:25,300:35,500:180 `
  --channels 16 `
  --monitor-aws `
  --poll-interval 25
```

> **Observação para a apresentação ao vivo:** O alarme `TargetTracking` de `CPUUtilization` (`AWS/ECS`) exige **3 pontos consecutivos de 60s >= 70%** e possui atraso natural de publicação/avaliação de métricas no CloudWatch de **~3 a 4 minutos** após o início da carga sustentada. Por isso, o estágio final mantém pressão por `180s`.

Para consultar a reação no ECS e no Application Auto Scaling:

```powershell
aws ecs describe-services --cluster ferry-cluster-prod `
  --services ferry-central-ingestion-prod ferry-central-worker-prod `
  --query "services[].{Name:serviceName,Desired:desiredCount,Running:runningCount,Pending:pendingCount}"

aws application-autoscaling describe-scaling-activities `
  --service-namespace ecs --max-results 5
```

### 1.2. Resultados reais medidos (18/11/2026)

Configuração sob teste: `ferry-central-ingestion-prod` (`0.5 vCPU` / `1024 MiB`), `ferry-central-worker-prod` (`0.25 vCPU` / `512 MiB`), `RDS db.t4g.micro`, cliente executando fora da VPC (Brasil -> `us-east-1` via ALB TLS `:50051`, deadline `2500 ms`, 16 canais HTTP/2).

#### Linha de base (1 barco enviando a cada 5s)
- `ferry-central-ingestion-prod`: CPU média `~0,75%`
- `ferry-db-writer-queue`: `0` mensagens visíveis

#### Rampa com 1 tarefa de Ingestão

| Estágio (Concorrência / Duração) | Total / OK | Vazão OK | Erros (`DEADLINE_EXCEEDED`) | Latência p50 / p95 / p99 | Estado |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `10` workers / `10s` (smoke) | `774 / 774` | `76,5 req/s` | `0 (0,00%)` | `119,7 / 142,2 / 609,7 ms` | Saudável |
| `50` workers / `20s` | `2.545 / 2.545` | `125,2 req/s` | `0 (0,00%)` | `381,5 / 609,1 / 929,4 ms` | Saudável (teto de vazão atingido) |
| `150` workers / `25s` | `3.209 / 3.209` | `123,3 req/s` | `0 (0,00%)` | `1.191,3 / 1.528,2 / 1.792,8 ms` | Fila saturando |
| **`300` workers / `35s`** | `4.656 / 4.210` | `114,2 req/s` | **`446 (9,58%)`** | **`2.386,5 / 2.504,4 / 2.507,3 ms`** | **Ponto de Quebra** |
| **`500` workers / `180s`** | `36.215 / 742` | `4,1 req/s` | **`35.473 (97,95%)`** | **`2.506,4 / 2.511,3 / 2.522,0 ms`** | **Colapso sustentado** |

#### CPU no CloudWatch e disparo do Auto Scaling
Durante o estágio sustentado, a métrica `AWS/ECS CPUUtilization` da tarefa de ingestão atingiu:
- `15:32:00`: `57,82%` (máx. `99,95%`)
- `15:33:00`: **`90,99%`**
- `15:34:00`: **`99,91%`**
- `15:35:00`: **`99,87%`**
- `15:36:00`: **`99,88%`**

Às `15:38:59`, o alarme `TargetTracking-service/ferry-cluster-prod/ferry-central-ingestion-prod-AlarmHigh` entrou em `ALARM` e acionou a política `ferry-ingestion-cpu-target-tracking-prod`, escalando `DesiredCount` de **`1` para `2`**. Às `15:40:05` (`~66s` depois), as **2 tarefas** já estavam `RUNNING` e saudáveis no ALB.

#### Ganho comprovado após o Auto Scaling (`2` tarefas ativas)
Repetindo exatamente o estágio de `150` concorrentes por `20s` com as `2` tarefas escaladas:
- **Vazão:** `4.839 / 4.839 OK` (`229,6 req/s` -> **`+86%` de vazão**)
- **Erros:** **`0 (0,00%)`**
- **Latência:** média `635,3 ms`, `p50 = 674,3 ms` (**`-43%`**), `p95 = 1.226,0 ms`, `p99 = 1.345,4 ms`

#### Diagnóstico arquitetural observado (Gargalo Ingestão vs. Worker SQS)
Durante todo o pico de `~125 req/s`, `1` única tarefa do `ferry-central-worker-prod` (`0.25 vCPU`, consumo em lotes de `50` mensagens) drenou a fila `ferry-db-writer-queue` mantendo-a entre `0` e `49` mensagens visíveis — abaixo do limiar de `100` mensagens por 3 minutos. Isso comprova que:
1. O primeiro gargalo sob rajada gRPC é a CPU / pool síncrono de publicação SNS do serviço de **Ingestão** (que escalou primeiro).
2. O Auto Scaling do **Worker** atua como segunda linha de defesa caso múltiplas réplicas de ingestão (ou drenagem simultânea de vários barcos pós-partição) mantenham backlog `>= 100` mensagens na fila SQS por 3 minutos.

---

## 2. Cenário 2 — Engenharia do Caos: Chaos Node Kill (`C3` + Bancada #1)

### 2.1. Como reproduzir ao vivo
Derrubar simultaneamente a única tarefa do Worker e uma das tarefas da Ingestão durante tráfego gRPC ativo:

```powershell
$workerTask = aws ecs list-tasks --cluster ferry-cluster-prod --service-name ferry-central-worker-prod --desired-status RUNNING --query "taskArns[0]" --output text
$ingTask = aws ecs list-tasks --cluster ferry-cluster-prod --service-name ferry-central-ingestion-prod --desired-status RUNNING --query "taskArns[0]" --output text

aws ecs stop-task --cluster ferry-cluster-prod --task $workerTask --reason "Chaos Node Kill Test (worker)"
aws ecs stop-task --cluster ferry-cluster-prod --task $ingTask --reason "Chaos Node Kill Test (ingestion)"

.\ferry-central\.venv\Scripts\python.exe scripts/chaos_load_test.py --stages 10:35 --channels 4 --monitor-aws --poll-interval 15
```

Para auditar o estado após a recuperação:

```powershell
aws sqs get-queue-attributes --queue-url (terraform -chdir=terraform output -raw sqs_db_writer_queue_url) --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
aws sqs get-queue-attributes --queue-url (terraform -chdir=terraform output -raw sqs_dlq_url) --attribute-names ApproximateNumberOfMessages
Invoke-RestMethod "http://<EC2_BARCO_IP>/api/edge/telemetry/buffer/status"
```

### 2.2. Resultado real medido (18/11/2026)
- **Queda simulada (`15:41:59`):** `worker` caiu para `running: 0` e `ingestion` caiu de `2` para `1` tarefa ativa.
- **Impacto na entrada gRPC (`35s` a `10` concorrentes):** **`2.782 / 2.782 OK` (`79,1 req/s`, `0,00%` de erros)**, latência `p50 = 120,5 ms` e `p95 = 152,6 ms` — o ALB roteou normalmente para a réplica sobrevivente sem derrubar a ingestão.
- **Amortecimento na mensageria (`15:42:16`):** enquanto o `worker` esteve fora (`running: 0, pending: 1`), a fila `ferry-db-writer-queue` absorveu **`1.572` mensagens** sem perder nenhuma requisição.
- **Autorrecuperação (`15:42:34` -> `15:42:47`):** em ~`35s` o ECS colocou o novo Worker em `running: 1`, a fila SQS baixou de `1.572 -> 172 -> 0` mensagens pendentes, a **DLQ permaneceu com `0` mensagens**, e o buffer local do barco real (`ferry-ivete-sangalo`) permaneceu em `state: "idle"` com `pending_count: 0`.
