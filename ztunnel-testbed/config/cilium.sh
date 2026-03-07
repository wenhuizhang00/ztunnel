#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Cilium Configuration
# =============================================================================
# Used by install-cilium.sh. Istio ambient compatible:
#   cni.exclusive=false, socketLB.hostNamespaceOnly=true, kubeProxyReplacement=false
# =============================================================================

# Cilium version (e.g. 1.16.0, 1.19.1)
export CILIUM_VERSION="${CILIUM_VERSION:-1.16.0}"
