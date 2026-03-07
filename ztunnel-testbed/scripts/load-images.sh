#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Load local images into cluster
# =============================================================================
# For kind/minikube/bare-metal: makes locally-built images available to the cluster.
# Run after make build-images. Detects cluster type and loads accordingly.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true
[ -f "${PROJECT_ROOT}/config/local.sh" ] && source "${PROJECT_ROOT}/config/local.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/config/images.sh" 2>/dev/null || true

IMAGE_REGISTRY="${IMAGE_REGISTRY:-localhost/ztunnel-testbed}"
IMAGES=("${IMAGE_REGISTRY}/http-echo:latest" "${IMAGE_REGISTRY}/curl-client:latest" "${IMAGE_REGISTRY}/fortio:latest")

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Detect cluster type
if command -v kind &>/dev/null && kind get clusters &>/dev/null 2>&1; then
  CLUSTER_TYPE="kind"
elif command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1; then
  CLUSTER_TYPE="minikube"
else
  CLUSTER_TYPE="unknown"
fi

if [[ "$CLUSTER_TYPE" == "kind" ]]; then
  log_info "Loading images into kind cluster..."
  for img in "${IMAGES[@]}"; do
    if docker image inspect "$img" &>/dev/null; then
      kind load docker-image "$img"
      log_ok "Loaded $img"
    else
      log_error "Image not found: $img. Run make build-images first."
    fi
  done
elif [[ "$CLUSTER_TYPE" == "minikube" ]]; then
  log_info "Loading images into minikube..."
  for img in "${IMAGES[@]}"; do
    if docker image inspect "$img" &>/dev/null; then
      minikube image load "$img"
      log_ok "Loaded $img"
    else
      log_error "Image not found: $img. Run make build-images first."
    fi
  done
else
  log_info "Cluster type: $CLUSTER_TYPE"
  echo "  For bare metal: images built on the same node are available to local containerd."
  echo "  For kind: install kind and run 'kind load docker-image <image>'"
  echo "  For minikube: run 'minikube image load <image>'"
  echo ""
  echo "  Images to load:"
  for img in "${IMAGES[@]}"; do echo "    $img"; done
fi
