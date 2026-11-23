# DNS público e domínio (SCRUM-29)

O domínio `rioswesley.com.br` é registrado no Registro.br e tem a zona servida pelo
Route 53 (`terraform/dns.tf`).

| Nome | Registro | Destino | Uso |
|---|---|---|---|
| `telemetry.rioswesley.com.br` | A (Alias) | ALB `ferry-alb-prod` | Ingestão gRPC em `:50051` com mTLS |
| `painel.rioswesley.com.br` | A (Alias) | ALB `ferry-alb-prod` | Dashboard e API REST em HTTPS (`:443`) |
| `capitao.rioswesley.com.br` | A | Elastic IP `ferry_barco_eip` | Painel do Capitão em HTTP (`:80`) |

## Certificados

- **`:443` (painel):** certificado público `*.rioswesley.com.br` da ACM, validado por DNS
  na própria zona. `http://painel…` redireciona para HTTPS; o DNS bruto do ALB continua
  respondendo em HTTP.
- **`:50051` (telemetry):** continua com o certificado da CA privada do projeto (SCRUM-34),
  que já traz `telemetry.rioswesley.com.br` no SAN. O barco confia nessa CA
  (`GRPC_TLS_CA_PATH`) e apresenta o próprio certificado de cliente.

## Registros preservados

Antes da SCRUM-29 o domínio já resolvia pelo DNS do Registro.br: o apex aponta para o
Firebase Hosting e o e-mail usa o Zoho (MX, SPF e DKIM). Esses registros estão em
`dns_preserved_records` (`terraform/variables.tf`) e são recriados na zona do Route 53,
então nada para de funcionar na troca de nameservers.

Antes de trocar os nameservers, exporte a zona atual no painel do Registro.br e confira
se há algum registro que não está na lista. Se houver, acrescente em
`dns_preserved_records` e aplique de novo.

## Primeiro apply

A validação do certificado público só termina quando o Registro.br já delega o domínio
ao Route 53. Por isso a zona é criada primeiro:

1. Crie só a zona e os registros dela:

   ```bash
   terraform apply -target=aws_route53_zone.public -target=aws_route53_record.preserved
   terraform output route53_name_servers
   ```

2. No Registro.br, em **DNS → Alterar servidores DNS**, troque `e.sec.dns.br` e
   `f.sec.dns.br` pelos quatro nameservers do output.
3. Confira a delegação (pode levar de minutos a algumas horas):

   ```bash
   nslookup -type=NS rioswesley.com.br 1.1.1.1
   ```

4. Rode o apply completo. Ele cria os registros do projeto, o certificado público e o
   listener HTTPS, e espera a ACM validar o certificado (até 2 h):

   ```bash
   terraform apply
   ```

5. No `/opt/ferry-boat/.env` da EC2, remova `CENTRAL_GRPC_URL` se ele ainda apontar para o
   DNS do ALB. O compose da borda usa `telemetry.rioswesley.com.br:50051` por padrão.
   Depois rode o workflow *CD Edge* ou `docker compose up -d` em `/opt/ferry-boat`.

## Verificação

```bash
nslookup painel.rioswesley.com.br 1.1.1.1
curl -I https://painel.rioswesley.com.br/health
curl -I http://capitao.rioswesley.com.br/
```

O certificado de `https://painel.rioswesley.com.br` deve abrir no navegador sem aviso.
