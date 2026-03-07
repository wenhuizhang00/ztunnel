#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Build local container images
# =============================================================================
# Builds http-echo, curl-client, fortio. Tag with IMAGE_REGISTRY.
# Run: make build-images or ./scripts/build-images.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PROJECT_ROOT}/config/versions.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true
[ -f "${PROJECT_ROOT}/config/local.sh" ] && source "${PROJECT_ROOT}/config/local.sh" 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_step() { echo -e "${BLUE}[$(date '+%H:%M:%S')] [$1]${NC} $2"; }
log_step_ok() {
  local elapsed="${3:-}"
  [[ -n "$elapsed" ]] && echo -e "${GREEN}[$(date '+%H:%M:%S')] [$1] OK${NC} $2 (${elapsed})" || echo -e "${GREEN}[$(date '+%H:%M:%S')] [$1] OK${NC} $2"
}

IMAGE_REGISTRY="${IMAGE_REGISTRY:-localhost/ztunnel-testbed}"

check_cmd() {
  command -v "$1" &>/dev/null || { echo "Required: $1"; exit 1; }
}
check_cmd docker

log_info "Building local images (registry: ${IMAGE_REGISTRY})..."

# Build arch (default: native)
# CHOKE: docker build (network for base images, compilation)
BUILD_ARCH="${BUILD_ARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"

build_image() {
  local name="$1"
  local dir="$2"
  log_step "BUILD" "Building ${name} (may pull base images)..."
  build_start=$(date +%s)
  docker build -t "${IMAGE_REGISTRY}/${name}:latest" "${dir}"
  log_step_ok "BUILD" "${name}: ${IMAGE_REGISTRY}/${name}:latest" "$(( $(date +%s) - build_start ))s"
}

build_image http-echo "${PROJECT_ROOT}/images/http-echo"
build_image curl-client "${PROJECT_ROOT}/images/curl-client"
build_image fortio "${PROJECT_ROOT}/images/fortio"

echo ""
log_ok "All images built. Use IMAGE_REGISTRY=${IMAGE_REGISTRY} make deploy"
echo ""
