#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Version Configuration
# =============================================================================
# Override these variables in config/local.sh or via environment.
# =============================================================================

# Istio version (e.g., 1.29.0, 1.30.0)
export ISTIO_VERSION="${ISTIO_VERSION:-1.29.0}"

# Gateway API CRDs version (e.g., v1.4.0)
export GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.4.0}"
export GATEWAY_API_INSTALL_URL="${GATEWAY_API_INSTALL_URL:-https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml}"
