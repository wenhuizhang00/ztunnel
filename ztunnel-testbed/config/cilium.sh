#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Cilium Configuration
# =============================================================================
# Compatible with Istio ambient mode (cni.exclusive=false, socketLB.hostNamespaceOnly=true)
# =============================================================================

# Cilium version (e.g. 1.16.0, 1.19.1)
export CILIUM_VERSION="${CILIUM_VERSION:-1.16.0}"
