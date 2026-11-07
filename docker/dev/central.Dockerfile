# Imagem de desenvolvimento da Central (Python 3.14) com hot-reload.
# O código é montado via bind mount pelo docker-compose.local.yml.
FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # Bind mounts no Windows/macOS não propagam eventos inotify
    WATCHFILES_FORCE_POLLING=true

WORKDIR /app

RUN pip install --no-cache-dir "watchfiles>=1.0"

# Instala dependências se o projeto já declarar um requirements.txt
RUN --mount=type=bind,source=.,target=/src \
    if [ -f /src/requirements.txt ]; then pip install --no-cache-dir -r /src/requirements.txt; fi

EXPOSE 50051

# Reinicia o servidor gRPC a cada alteração em src/
CMD ["watchfiles", "--filter", "python", "python -m src.server.main", "src"]
