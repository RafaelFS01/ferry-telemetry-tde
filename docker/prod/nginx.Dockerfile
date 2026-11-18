# Imagem de produção dos proxies Nginx (contexto: raiz do repositório)
#   --build-arg SITE=edge     Borda do Barco (ferry-nginx-edge)
#   --build-arg SITE=central  Borda da Central
FROM nginx:1.27-alpine
ARG SITE
COPY docker/nginx/snippets /etc/nginx/snippets
COPY docker/nginx-${SITE}.conf /etc/nginx/templates/default.conf.template
# Em produção não há HMR: a CSP não libera eval
ENV NGINX_RESOLVER=127.0.0.11 \
    CSP_SCRIPT_EXTRA=""
HEALTHCHECK --interval=15s --timeout=3s CMD wget -qO- http://127.0.0.1/healthz || exit 1
