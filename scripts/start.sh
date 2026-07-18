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
docker compose -f compose.lab.yml build
docker compose -f compose.lab.yml up -d

# Wait for SSH
sleep 3

# Test connectivity
echo ""
echo "Testing SSH..."
for port in 2201 2202 2203 2204 2205; do
    ssh -i "$HOME/.ssh/personal" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -p "$port" ansible@localhost \
        "echo OK: $(hostname)" 2>/dev/null && \
        echo "  $port: OK" || echo "  $port: pending"
done

echo ""
echo "Lab ready! Test with: ansible all -m ping -i inventory.ini"
