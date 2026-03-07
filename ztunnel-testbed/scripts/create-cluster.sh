#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Verify Kubernetes cluster connectivity
# =============================================================================
# Does NOT create a cluster. Verifies kubectl can reach an existing cluster.
# Create cluster first: make create-baremetal (bare metal) or minikube/kind.
# Config: KUBECONFIG, KUBE_CONTEXT (config/local.sh)
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log_info "Step 1/4: Checking kubectl..."
check_cmd kubectl
log_ok "kubectl found: $(command -v kubectl)"

log_info "Step 2/4: Verifying kubeconfig..."
if [[ -n "${KUBECONFIG:-}" ]]; then
  if [[ -f "${KUBECONFIG}" ]]; then
    log_ok "KUBECONFIG=${KUBECONFIG} exists"
  else
    log_warn "KUBECONFIG=${KUBECONFIG} not found"
    if [[ -f "$HOME/.kube/config" ]]; then
      export KUBECONFIG="$HOME/.kube/config"
      log_ok "Using ~/.kube/config instead (control-plane default)"
    fi
  fi
else
  if [[ -f "$HOME/.kube/config" ]]; then
    log_ok "Using default ~/.kube/config"
  else
    log_warn "No KUBECONFIG set and ~/.kube/config not found"
  fi
fi

log_info "Step 3/4: Connecting to cluster..."
ensure_kubectl_context

log_info "Step 4/4: Cluster info"
log_ok "Connected to cluster."
kubectl cluster-info
log_info "Nodes:"
kubectl get nodes -o wide 2>/dev/null || true
