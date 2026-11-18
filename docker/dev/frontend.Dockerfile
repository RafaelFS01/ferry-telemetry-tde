# Imagem de desenvolvimento dos frontends Next.js 16 (Painel do Capitão e Dashboard).
# Código via bind mount; node_modules e .next ficam em volumes nomeados.
FROM node:24-alpine

ENV NEXT_TELEMETRY_DISABLED=1 \
    # Bind mounts no Windows/macOS não propagam eventos inotify;
    # lido pelo next.config.ts (watchOptions.pollIntervalMs do Turbopack)
    NEXT_WATCH_POLL_MS=1000

WORKDIR /app

EXPOSE 3000

CMD ["sh", "-c", "if [ -f package-lock.json ]; then npm ci; else npm install; fi && exec npm run dev"]
