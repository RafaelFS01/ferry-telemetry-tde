# Imagem de produção do Nó Barco (contexto: raiz do repositório, pois o build
# compila os stubs a partir de proto/telemetry.proto)

FROM node:24-alpine AS build
WORKDIR /build/ferry-boat
COPY ferry-boat/package.json ferry-boat/package-lock.json ./
RUN npm ci
COPY proto /build/proto
COPY ferry-boat ./
# build gera os stubs, compila o NestJS e copia o .proto para dist/proto
RUN npm run build && npm prune --omit=dev

FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build --chown=node:node /build/ferry-boat/package.json ./
COPY --from=build --chown=node:node /build/ferry-boat/node_modules ./node_modules
COPY --from=build --chown=node:node /build/ferry-boat/dist ./dist
RUN mkdir -p /app/data && chown node:node /app/data
USER node
EXPOSE 3002
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s \
  CMD node -e "fetch('http://127.0.0.1:3002/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/main.js"]
