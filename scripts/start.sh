#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUB_KEY="$HOME/.ssh/personal.pub"

# Check prerequisites
command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
[ -f "$PUB_KEY" ] || { echo "Error: $PUB_KEY not found"; exit 1; }

cd "$ROOT_DIR"

echo "=== Starting PatchOps Platform (govdb + grafana) ==="
docker compose up -d

echo ""
echo "=== Starting PatchOps Lab (aptly + servers) ==="
# SSH_PUBKEY is baked into the lab images at build time (see docker/*.Dockerfile)
# instead of being bind-mounted in at runtime.
export SSH_PUBKEY
SSH_PUBKEY="$(cat "$PUB_KEY")"
docker compose -f compose.lab.yml up -d --build

echo ""
if [ -f "$ROOT_DIR/awx/.env" ]; then
    echo "=== Starting AWX ==="
    cd "$ROOT_DIR/awx"
    docker compose up -d
    cd "$ROOT_DIR"
else
    echo "=== Skipping AWX (awx/.env not found — copy awx/.env.example and fill it in to enable) ==="
fi

# Wait for SSH — sshd itself starts quickly since it's baked into the image,
# but this can still take a while if the images above just got (re)built, or
# if the aptly mirror sync is competing for the same network egress. A fixed
# short sleep is not reliable here — poll each host until it actually answers
# instead of guessing a delay.
echo ""
echo "Waiting for SSH on all 5 lab servers (up to 3 minutes)..."
for port in 2201 2202 2203 2204 2205; do
    ready=false
    for _ in $(seq 1 36); do
        if ssh -i "$HOME/.ssh/personal" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -p "$port" ansible@127.0.0.1 \
            'echo "OK: $(hostname)"' 2>/dev/null; then
            echo "  $port: OK"
            ready=true
            break
        fi
        sleep 5
    done
    [ "$ready" = true ] || echo "  $port: still not reachable after 3 minutes — check: docker logs \$(docker ps --filter publish=$port -q)"
done

echo ""
echo "Lab ready! Test with: ansible all -m ping -i inventory.ini"
