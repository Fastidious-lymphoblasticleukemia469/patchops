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
docker compose -f compose.lab.yml up -d

# Wait for SSH — these are stock ubuntu:24.04 images that install
# openssh-server fresh on every boot (nothing but /var/cache/aptly and the
# client home dirs persist across restarts), so this can genuinely take well
# over a minute, especially if the aptly mirror sync is competing for the
# same network egress. A fixed short sleep is not reliable here — poll each
# host until it actually answers instead of guessing a delay.
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
