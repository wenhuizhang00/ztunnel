#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Common utilities for scripts
# =============================================================================

set -euo pipefail

# Resolve script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load config
source "${PROJECT_ROOT}/config/versions.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true
[ -f "${PROJECT_ROOT}/config/local.sh" ] && source "${PROJECT_ROOT}/config/local.sh" 2>/dev/null || true

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
    log_error "Cannot reach Kubernetes cluster. Check KUBECONFIG and kubectl context."
    return 1
  fi
  return 0
}
