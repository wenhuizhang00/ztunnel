#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Common utilities for scripts
# =============================================================================

set -euo pipefail

# Resolve script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load config (local.sh before images.sh so USE_LOCAL_IMAGES can be set)
source "${PROJECT_ROOT}/config/versions.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true
[ -f "${PROJECT_ROOT}/config/local.sh" ] && source "${PROJECT_ROOT}/config/local.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/config/images.sh" 2>/dev/null || true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Choke-point logging: timestamp + phase for long-running steps
log_step() {
  local ts phase msg
  ts=$(date '+%H:%M:%S')
  phase="${1:-STEP}"
  msg="${2:-}"
  echo -e "${BLUE}[${ts}] [${phase}]${NC} ${msg}"
}
log_step_ok() {
  local ts phase msg elapsed
  ts=$(date '+%H:%M:%S')
  phase="${1:-STEP}"
  msg="${2:-done}"
  elapsed="${3:-}"
  [[ -n "$elapsed" ]] && msg="${msg} (${elapsed})"
  echo -e "${GREEN}[${ts}] [${phase}] OK${NC} ${msg}"
}
# Usage: STEP_START=$(date +%s); ... ; log_step_ok "PHASE" "message" "$(( $(date +%s) - STEP_START ))s"

# Check command exists
check_cmd() {
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command not found: $cmd"
      return 1
    fi
  done
  return 0
}

# Ensure kubectl can reach cluster (switch context if KUBE_CONTEXT set)
ensure_kubectl_context() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl config use-context "${KUBE_CONTEXT}" 2>/dev/null || {
      log_error "Failed to switch to context ${KUBE_CONTEXT}."
      return 1
    }
  fi
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot reach Kubernetes cluster."
    echo ""
    if [[ -n "${KUBECONFIG:-}" ]]; then
      if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "  KUBECONFIG=${KUBECONFIG} points to a file that does not exist."
        echo "  Create a cluster first, then copy kubeconfig from the control-plane."
      else
        echo "  KUBECONFIG=${KUBECONFIG} exists but cluster is unreachable (API server down, wrong host, or firewall)."
      fi
      echo ""
    fi
    echo "  Next steps:"
    echo "  1. Create a cluster first. Options:"
    echo "     - Bare metal:  make create-baremetal  (run on control-plane node; install kubeadm first)"
    echo "     - Minikube:    minikube start"
    echo "     - Kind:        kind create cluster"
    echo "  2. Or point kubectl to existing cluster:"
    echo "     export KUBECONFIG=/path/to/kubeconfig"
    echo "     kubectl config use-context <context>"
    echo "  3. Verify:  kubectl cluster-info"
    echo ""
    return 1
  fi
  return 0
}
