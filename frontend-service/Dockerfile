# syntax=docker/dockerfile:1.7
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/nginx.conf
COPY public /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
