#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Fix kubeconfig for control-plane
# =============================================================================
# Use when kubectl shows "localhost:8080 refused" - usually KUBECONFIG points
# to non-existent file (e.g. ztunnel-baremetal-config) or ~/.kube/config missing.
# Run on control-plane node.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${PROJECT_ROOT}/scripts/common.sh" 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "\033[0;33m[WARN]${NC} $*"; }

log_info "Fixing kubeconfig for control-plane..."

# 1. Ensure admin.conf exists (cluster must be created)
if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  echo -e "${RED}[ERROR]${NC} /etc/kubernetes/admin.conf not found. Create cluster first: make create-baremetal"
  exit 1
fi
log_ok "/etc/kubernetes/admin.conf exists"

# 2. Copy to user kubeconfig
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
log_ok "Copied to ~/.kube/config"

# 3. Unset KUBECONFIG if it points to non-existent file (current shell only)
if [[ -n "${KUBECONFIG:-}" ]] && [[ ! -f "${KUBECONFIG}" ]]; then
  log_warn "KUBECONFIG=${KUBECONFIG} points to non-existent file."
  unset KUBECONFIG
  export KUBECONFIG="$HOME/.kube/config"
  log_ok "Using ~/.kube/config for this shell"
fi

# 4. Verify
if kubectl cluster-info &>/dev/null; then
  log_ok "kubectl works. Run: kubectl get nodes"
  kubectl get nodes 2>/dev/null || true
else
  log_warn "kubectl still fails. In a NEW shell, run:"
  echo "  unset KUBECONFIG"
  echo "  export KUBECONFIG=\$HOME/.kube/config"
  echo ""
  echo "If KUBECONFIG is in ~/.bashrc or ~/.profile, remove or fix it."
  exit 1
fi

echo ""
log_ok "Done. For new shells, add to ~/.bashrc or run before make:"
echo "  export KUBECONFIG=\$HOME/.kube/config"
echo "  # Or remove KUBECONFIG=.../ztunnel-baremetal-config from config/local.sh if on control-plane"
