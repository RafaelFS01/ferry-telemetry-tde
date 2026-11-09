# Imagem de desenvolvimento do Nó Barco (NestJS 12 / Node 24) com hot-reload.
# O código é montado via bind mount; node_modules fica em volume nomeado.
FROM node:24-alpine

# Usa o protoc compilado para musl; os binários npm de grpc-tools usam glibc.
RUN apk add --no-cache protobuf

ENV NODE_ENV=development \
    PROTOC_PATH=/usr/bin/protoc \
    # Bind mounts no Windows/macOS não propagam eventos inotify
    CHOKIDAR_USEPOLLING=true

WORKDIR /app

EXPOSE 3002

# Dependências são instaladas no start porque o volume de node_modules
# sobrepõe o que estiver na imagem; `nest start --watch` faz o hot-reload.
CMD ["sh", "-c", "if [ -f package-lock.json ]; then npm ci; else npm install; fi && exec npm run start:dev"]
