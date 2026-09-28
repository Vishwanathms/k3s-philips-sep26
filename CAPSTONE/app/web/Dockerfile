# Capstone web tier: static page + reverse proxy to the API tier.
# nginx-unprivileged runs as non-root (UID 101) on port 8080, so it passes
# Day 11's "restricted" Pod Security profile without changes.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# API_UPSTREAM defaults to the Service name + port of the python tier.
ENV API_UPSTREAM=api:8000 \
    WEB_VERSION=1.0.0

# The image renders /etc/nginx/templates/*.template -> /etc/nginx/conf.d/*
# with envsubst at startup, replacing the stock default.conf.
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY html/ /usr/share/nginx/html/

EXPOSE 8080
