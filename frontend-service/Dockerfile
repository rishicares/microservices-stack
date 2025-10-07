# syntax=docker/dockerfile:1.7
FROM nginx:1.27-alpine

# Set up directories with proper permissions for nginx user
RUN mkdir -p /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp && \
    chown -R nginx:nginx /var/log/nginx /var/run /usr/share/nginx/html /tmp && \
    chmod -R 755 /tmp

COPY nginx.conf /etc/nginx/nginx.conf
COPY public /usr/share/nginx/html

# Ensure proper ownership
RUN chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
