#!/usr/bin/env bash
# Build and optionally push 2ssk/patchops-ee as a multi-arch image.
#
# Usage:
#   ./build.sh                   # build only (local, current arch)
#   ./build.sh --push            # build + push multi-arch to Docker Hub
#
# Prerequisites (one-time setup):
#   pip install ansible-builder
#   docker login
#   docker buildx create --use --name multiarch --driver docker-container
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="2ssk/patchops-ee"
TAG="latest"
PUSH=false
PLATFORMS="linux/amd64,linux/arm64"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --push)       PUSH=true; shift ;;
        --platforms)  PLATFORMS="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Step 1 — use ansible-builder to generate the build context (Containerfile
# + _build/ scripts). This does NOT build an image.
# ---------------------------------------------------------------------------
echo "[ee-build] Generating build context with ansible-builder..."
ansible-builder create \
    -f "$SCRIPT_DIR/execution-environment.yml" \
    --context "$SCRIPT_DIR/context" \
    --output-filename Containerfile

echo "[ee-build] Context written to $SCRIPT_DIR/context"

# ---------------------------------------------------------------------------
# Step 2 — multi-arch build via docker buildx
# ---------------------------------------------------------------------------
if ! docker buildx inspect multiarch &>/dev/null; then
    echo "[ee-build] Creating docker-container buildx builder 'multiarch'..."
    docker buildx create --name multiarch --driver docker-container --use
else
    docker buildx use multiarch
fi

if ! $PUSH; then
    NATIVE_ARCH="$(docker info --format '{{.Architecture}}')"
    case "$NATIVE_ARCH" in
        aarch64|arm64) PLATFORMS="linux/arm64" ;;
        *)             PLATFORMS="linux/amd64" ;;
    esac
    echo "[ee-build] Local load — building for native arch only: $PLATFORMS"
fi

echo "[ee-build] Platforms : $PLATFORMS"
echo "[ee-build] Tag       : ${IMAGE}:${TAG}"
echo "[ee-build] Push      : $PUSH"
echo ""

PUSH_FLAG="--load"
if $PUSH; then
    PUSH_FLAG="--push"
fi

docker buildx build \
    --platform "$PLATFORMS" \
    -t "${IMAGE}:${TAG}" \
    -f "$SCRIPT_DIR/context/Containerfile" \
    $PUSH_FLAG \
    "$SCRIPT_DIR/context"

echo ""
echo "[ee-build] Done."
if $PUSH; then
    echo "[ee-build] Pushed: ${IMAGE}:${TAG}"
else
    echo "[ee-build] Image loaded locally as ${IMAGE}:${TAG}"
fi
