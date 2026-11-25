# Kinetune frontend: build the SPA with Node, serve the static files with an
# unprivileged nginx (no Node, no build tools in the runtime image).
FROM node:22.12-alpine AS build
WORKDIR /app
# dependencies first: this layer is cached until package*.json change
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
# backend address used by the /api proxy (envsubst at container start)
ENV BACKEND_URL=http://backend:8000
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
# the base image already runs as the non-root user "nginx" (uid 101)
USER 101
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
