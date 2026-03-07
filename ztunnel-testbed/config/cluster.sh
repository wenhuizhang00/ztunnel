#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Cluster Configuration
# =============================================================================
# Use an existing Kubernetes cluster. Set KUBECONFIG or switch context.
# =============================================================================

# Optional: specific kubectl context to use (empty = use current)
export KUBE_CONTEXT="${KUBE_CONTEXT:-}"
