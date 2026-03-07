#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Cluster Configuration
# =============================================================================
# Use an existing Kubernetes cluster. Set KUBECONFIG or switch context.
# =============================================================================

# Optional: path to kubeconfig (set in config/local.sh or export before make)
export KUBECONFIG="${KUBECONFIG:-}"

# Optional: kubectl context (default: grimlock-cell for bare metal; override in local.sh)
export KUBE_CONTEXT="${KUBE_CONTEXT:-grimlock-cell}"

# Sample app namespaces
export APP_NAMESPACE="${APP_NAMESPACE:-grimlock}"
export APP_NAMESPACE_BASELINE="${APP_NAMESPACE_BASELINE:-grimlock-baseline}"
