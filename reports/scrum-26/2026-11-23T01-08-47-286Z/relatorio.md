# SCRUM-26 — Ensaio de partição de rede de 24h

- Execução: 2026-11-23T01:08:47.286Z (23.4 min)
- Resultado: **APROVADO**
- Parâmetros: 17280 pacotes, coleta acelerada a cada 20ms (250x), partição `blackhole`

| Critério | Resultado | Evidência |
| :--- | :---: | :--- |
| Partição da rota gRPC durante a navegação | OK | modo=blackhole; estados observados: draining, offline |
| Acúmulo contínuo em disco sem consumo excessivo de RAM | OK | 17347 pacotes retidos; RAM <= 5000 itens (máx. 5000); disco=12325; RSS após janela cheia +0 MiB (limite 64); reinício preservou 17347 |
| Reativação do link e drenagem ordenada | OK | 18.46 pacotes/s em 939.5s; 17347/17347 ACKs em ordem FIFO (fora de ordem: 0) |
| 100% dos pacotes na Central com sequência e timestamp preservados | OK | 17347/17347 no PostgreSQL; divergências: seq=0, ts=0, payload=0, boat=0 |
| Drenagem sem estouro de memória na Central (proteção SQS) | OK | ferry-central: pico 118.6 MiB / limite 512 MiB; ferry-worker: pico 80.9 MiB / limite 512 MiB; backlog SQS máx. 47, final 0, DLQ 0 |

## Linha do tempo

- Partição: 2026-11-23T01:09:13.954Z -> restauração 2026-11-23T01:15:17.171Z
- Acúmulo: 350s até 17347 pacotes (seq 58..17404)
- Circuit breaker do barco na partição: CLOSED, OPEN, HALF_OPEN; CLOSED com ACK 3.1s após a restauração
- Drenagem: 939.5s (18.46 pacotes/s)
- Fila SQS: pico 47 mensagens; esvaziada em 71s após a drenagem
