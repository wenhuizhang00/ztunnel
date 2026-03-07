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

log_info "Checking Kubernetes cluster connectivity..."

check_cmd kubectl

ensure_kubectl_context

log_ok "Connected to cluster."
kubectl cluster-info
log_info "Nodes:"
kubectl get nodes -o wide 2>/dev/null || true
