# Imagens de produção do Nó Central (contexto: ./ferry-central)
#   --target ingestion  servidor gRPC + API REST (ECS service ferry-central-ingestion)
#   --target worker     consumidor SQS com escrita em lote (ECS service ferry-central-worker)

FROM python:3.14-slim AS deps
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
COPY requirements.txt /tmp/requirements.txt
RUN python -m venv /opt/venv && /opt/venv/bin/pip install -r /tmp/requirements.txt

FROM python:3.14-slim AS base
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
RUN useradd --system --uid 10001 --no-create-home ferry
COPY --from=deps /opt/venv /opt/venv
COPY alembic.ini ./
COPY alembic ./alembic
COPY src ./src
USER ferry

FROM base AS ingestion
EXPOSE 50051 8000
CMD ["python", "-m", "src.server.main"]

FROM base AS worker
# Ponto de entrada do consumidor SQS definido pela SCRUM-17
CMD ["python", "-m", "src.worker.main"]
