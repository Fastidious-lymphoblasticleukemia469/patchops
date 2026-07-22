#!/usr/bin/env bash
# Build and optionally push 2ssk/awx-standalone as a multi-arch image.
#
# Usage:
#   ./build.sh                        # build only (no push)
#   ./build.sh --push                 # build + push to Docker Hub
#   ./build.sh --version 24.6.1       # override AWX version tag
#   ./build.sh --push --version 25.0  # combined
#
# Prerequisites (one-time setup):
#   docker login                      # authenticate with Docker Hub
#   docker buildx create --use --name multiarch --driver docker-container
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="2ssk/awx-standalone"
VERSION="24.6.1"
PUSH=false
PLATFORMS="linux/amd64,linux/arm64"

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --push)       PUSH=true; shift ;;
        --version)    VERSION="$2"; shift 2 ;;
        --platforms)  PLATFORMS="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,13p' "$0"   # print the usage block at the top
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

TAGS=(-t "${IMAGE}:${VERSION}" -t "${IMAGE}:latest")

# ---------------------------------------------------------------------------
# Ensure a buildx builder that supports multi-arch exists
# ---------------------------------------------------------------------------
if ! docker buildx inspect multiarch &>/dev/null; then
    echo "[build] Creating docker-container buildx builder 'multiarch'..."
    docker buildx create --name multiarch --driver docker-container --use
else
    docker buildx use multiarch
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "[build] Platforms : $PLATFORMS"
echo "[build] Tags      : ${IMAGE}:${VERSION}, ${IMAGE}:latest"
echo "[build] Push      : $PUSH"
echo ""

PUSH_FLAG="--load"
if $PUSH; then
    PUSH_FLAG="--push"
    # --load only works for single-platform; multi-arch requires --push
fi

# When only building locally (--load), limit to the current machine's arch
# because --load doesn't support manifests with multiple platforms.
if ! $PUSH; then
    NATIVE_ARCH="$(docker info --format '{{.Architecture}}')"
    case "$NATIVE_ARCH" in
        aarch64|arm64) PLATFORMS="linux/arm64" ;;
        *)             PLATFORMS="linux/amd64" ;;
    esac
    echo "[build] Local load — building for native arch only: $PLATFORMS"
fi

docker buildx build \
    --platform "$PLATFORMS" \
    "${TAGS[@]}" \
    --build-arg AWX_VERSION="$VERSION" \
    $PUSH_FLAG \
    "$SCRIPT_DIR"

echo ""
echo "[build] Done."
if $PUSH; then
    echo "[build] Pushed: ${IMAGE}:${VERSION} and ${IMAGE}:latest"
else
    echo "[build] Image loaded locally as ${IMAGE}:${VERSION}"
    echo "[build] Run with: cd awx && docker compose up -d"
fi
