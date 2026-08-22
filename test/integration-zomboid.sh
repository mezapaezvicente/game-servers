#!/usr/bin/env bash
# Real docker-compose integration test: builds a synthetic .env for zomboid,
# brings the real container up against the real pinned image, and waits for
# the healthcheck. This is the layer that would have caught the PUBLIC/
# SERVER_PUBLIC collision — `docker compose config` is exactly where that
# bug showed up (see todo.md, games/zomboid/README.md's Troubleshooting).
# Needs a real Docker daemon; skipped nowhere, but slow (image pull +
# 1-3 min JVM boot) — not meant to run on every keystroke.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../games/zomboid"

PROJECT="zomboid-ci-test"
ENV_FILE="$(mktemp)"
DATA_DIR="$(mktemp -d)"
trap 'docker compose -p "$PROJECT" --env-file "$ENV_FILE" down -v >/dev/null 2>&1 || true; rm -rf "$ENV_FILE" "$DATA_DIR"' EXIT

cp .env.example "$ENV_FILE"
# Distinct container name and scratch data dir so this never collides with
# a real zomboid instance someone has running locally. Ports come from
# .env.example as-is — CI runners don't have anything else bound to them.
sed -i "s|^GAME_NAME=.*|GAME_NAME=${PROJECT}|" "$ENV_FILE"
sed -i "s|^DATA_DIR=.*|DATA_DIR=${DATA_DIR}|" "$ENV_FILE"

echo "==> docker compose config (this is what catches env-var collisions like SERVER_PUBLIC's)"
docker compose -p "$PROJECT" --env-file "$ENV_FILE" config >/dev/null

echo "==> docker compose up -d"
docker compose -p "$PROJECT" --env-file "$ENV_FILE" up -d

echo "==> waiting for healthcheck (JVM boot is commonly 1-3+ minutes)"
i=0
while [ "$i" -lt 60 ]; do
  status="$(docker inspect --format='{{.State.Health.Status}}' "$(docker compose -p "$PROJECT" --env-file "$ENV_FILE" ps -q game)" 2>/dev/null || echo unknown)"
  if [ "$status" = "healthy" ]; then
    echo "==> healthy"
    exit 0
  fi
  if [ "$status" = "unhealthy" ]; then
    echo "==> unhealthy, dumping logs:"
    docker compose -p "$PROJECT" --env-file "$ENV_FILE" logs
    exit 1
  fi
  i=$((i + 1))
  sleep 10
done

echo "==> timed out waiting for healthy, dumping logs:"
docker compose -p "$PROJECT" --env-file "$ENV_FILE" logs
exit 1
