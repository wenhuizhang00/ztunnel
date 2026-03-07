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

# Verify and fix kubeconfig before cluster checks. Built into ensure_kubectl_context.
# Fixes applied automatically:
# - KUBECONFIG points to non-existent file -> use ~/.kube/config
# - ~/.kube/config missing but /etc/kubernetes/admin.conf exists (control-plane) -> copy it via sudo
ensure_valid_kubeconfig() {
  # 1. KUBECONFIG points to non-existent file -> fallback to ~/.kube/config
  if [[ -n "${KUBECONFIG:-}" ]] && [[ ! -f "${KUBECONFIG}" ]]; then
    if [[ -f "$HOME/.kube/config" ]]; then
      log_info "KUBECONFIG=${KUBECONFIG} not found (file does not exist). Using ~/.kube/config"
      export KUBECONFIG="$HOME/.kube/config"
      return 0
    else
      log_warn "KUBECONFIG=${KUBECONFIG} not found, and ~/.kube/config is missing. Will try control-plane copy next."
    fi
  fi

  # 2. No valid kubeconfig; on control-plane, try to copy admin.conf (requires sudo)
  local effective_config="${KUBECONFIG:-$HOME/.kube/config}"
  if [[ ! -f "$effective_config" ]] && [[ -f /etc/kubernetes/admin.conf ]]; then
    log_info "No kubeconfig found. Copying from /etc/kubernetes/admin.conf (control-plane)..."
    if mkdir -p "$HOME/.kube" 2>/dev/null && sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config" 2>/dev/null; then
      sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config" 2>/dev/null || true
      export KUBECONFIG="$HOME/.kube/config"
      log_ok "Copied /etc/kubernetes/admin.conf to ~/.kube/config"
      return 0
    else
      log_warn "Could not copy admin.conf (sudo may require password). Run manually: sudo cp /etc/kubernetes/admin.conf ~/.kube/config"
    fi
  fi

  return 0
}

# Ensure kubectl can reach cluster (switch context if KUBE_CONTEXT set)
# Auto-fix: KUBECONFIG to non-existent file -> use ~/.kube/config; missing config -> copy from admin.conf
ensure_kubectl_context() {
  ensure_valid_kubeconfig

  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl config use-context "${KUBE_CONTEXT}" 2>/dev/null || {
      log_error "Failed to switch to context ${KUBE_CONTEXT}."
      return 1
    }
  fi
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot reach Kubernetes cluster."
    echo ""
    # localhost:8080 = kubectl using empty/wrong config (KUBECONFIG to non-existent file)
    if kubectl config view --minify 2>/dev/null | grep -q 'server:.*8080'; then
      echo "  Root cause: kubectl is using localhost:8080 (invalid default)."
      echo "  This happens when KUBECONFIG points to a non-existent file."
      echo "  or when ~/.kube/config is missing. kubectl then falls back to the insecure port 8080."
      echo ""
      echo "  Fix (on control-plane):"
      echo "    unset KUBECONFIG"
      echo "    sudo cp -f /etc/kubernetes/admin.conf ~/.kube/config"
      echo "    sudo chown \$(id -u):\$(id -g) ~/.kube/config"
      echo ""
      echo "  Fix (if KUBECONFIG in config/local.sh or ~/.bashrc): remove or set to existing path."
      echo ""
    fi
    if [[ -n "${KUBECONFIG:-}" ]]; then
      if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "  KUBECONFIG=${KUBECONFIG}"
        echo "  -> File does not exist. On control-plane use ~/.kube/config. On workstation, copy first:"
        echo "     scp user@control-plane:~/.kube/config ~/.kube/config"
        echo ""
      else
        echo "  KUBECONFIG=${KUBECONFIG} exists but cluster is unreachable."
        echo "  -> API server may be down, wrong host, or firewall blocking. Check: kubectl cluster-info dump"
        echo ""
      fi
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
