#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Cluster Configuration
# =============================================================================
# Use an existing Kubernetes cluster. Set KUBECONFIG or switch context.
# =============================================================================

# Optional: kubectl context (empty = use current)
export KUBE_CONTEXT="${KUBE_CONTEXT:-}"

# Sample app namespaces
export APP_NAMESPACE="${APP_NAMESPACE:-grimlock}"
export APP_NAMESPACE_BASELINE="${APP_NAMESPACE_BASELINE:-grimlock-baseline}"
