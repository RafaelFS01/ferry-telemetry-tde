#!/bin/bash
# Executado pelo entrypoint oficial do Postgres apenas na primeira inicialização do volume.
# Cria o banco de telemetria; as tabelas ficam a cargo das migrações Alembic (SCRUM-9).
set -euo pipefail

: "${TELEMETRY_DB:?TELEMETRY_DB não definido}"

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname postgres <<-SQL
	SELECT 'CREATE DATABASE ${TELEMETRY_DB} OWNER ${POSTGRES_USER}'
	WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${TELEMETRY_DB}')\gexec
SQL

echo "[postgres-init] Banco ${TELEMETRY_DB} pronto."
