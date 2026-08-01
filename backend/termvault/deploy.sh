#!/bin/sh
set -eu

SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=/opt/termvault-cloud
CADDY_FILE=/etc/caddy/Caddyfile

install -d -m 0755 "$DEPLOY_DIR"
install -m 0644 "$SOURCE_DIR/server.py" "$DEPLOY_DIR/server.py"
install -m 0644 "$SOURCE_DIR/Dockerfile" "$DEPLOY_DIR/Dockerfile"
install -m 0644 "$SOURCE_DIR/compose.yml" "$DEPLOY_DIR/compose.yml"

docker compose -f "$DEPLOY_DIR/compose.yml" up -d --build

if ! grep -q 'handle_path /termvault-api/\*' "$CADDY_FILE"; then
    sed -i '/masystem.co.in, www.masystem.co.in {/a\
\thandle_path /termvault-api/* {\
\t\treverse_proxy 127.0.0.1:8791\
\t}' "$CADDY_FILE"
fi

caddy fmt --overwrite "$CADDY_FILE"
caddy validate --config "$CADDY_FILE"
systemctl reload caddy
