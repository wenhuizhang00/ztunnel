#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Verify Kubernetes cluster connectivity
# =============================================================================
# Uses an existing Kubernetes cluster. Ensure kubectl is configured.
# Run: kubectl config get-contexts
# Set: export KUBECONFIG=/path/to/kubeconfig
#      export KUBE_CONTEXT=my-context  (optional, in config/local.sh)
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log_info "Checking Kubernetes cluster connectivity..."

check_cmd kubectl

ensure_kubectl_context

log_ok "Connected to cluster."
kubectl cluster-info
log_info "Nodes:"
kubectl get nodes -o wide 2>/dev/null || true
