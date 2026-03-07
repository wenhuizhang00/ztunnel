#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Install Istio ambient mode
# =============================================================================
# 1. Download istioctl if needed
# 2. Install Gateway API CRDs
# 3. Install Istio with ambient profile (standard Kubernetes)
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

log_info "Installing Istio ambient mode (version: ${ISTIO_VERSION})"

# Detect OS and arch for Istio download
case "$(uname -s)" in
  Darwin) TARGET_OS=osx ;;
  Linux)  TARGET_OS=linux ;;
  *) TARGET_OS=linux ;;
esac
case "$(uname -m)" in
  x86_64)  TARGET_ARCH=x86_64 ;;
  arm64|aarch64) TARGET_ARCH=arm64 ;;
  *) TARGET_ARCH=x86_64 ;;
esac

# Ensure istioctl
ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
if [[ ! -x "${ISTIOCTL}" ]] || [[ ! -d "${PROJECT_ROOT}/.cache/istio-${ISTIO_VERSION}" ]]; then
  log_info "Downloading Istio ${ISTIO_VERSION}..."
  mkdir -p "${PROJECT_ROOT}/.cache"
  cd "${PROJECT_ROOT}/.cache"
  if [[ ! -d "istio-${ISTIO_VERSION}" ]]; then
    export ISTIO_VERSION TARGET_OS TARGET_ARCH
    curl -sL "https://istio.io/downloadIstio" | sh -
  fi
  mkdir -p "${PROJECT_ROOT}/bin"
  cp -f "${PROJECT_ROOT}/.cache/istio-${ISTIO_VERSION}/bin/istioctl" "${ISTIOCTL}"
  chmod +x "${ISTIOCTL}"
  cd "${PROJECT_ROOT}"
fi
log_ok "istioctl: $(${ISTIOCTL} version --short 2>/dev/null || ${ISTIOCTL} version 2>/dev/null | head -1)"

# Install Gateway API CRDs
log_info "Installing Gateway API CRDs (${GATEWAY_API_VERSION})..."
if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
  log_ok "Gateway API CRDs already installed."
else
  kubectl apply --server-side -f "${GATEWAY_API_INSTALL_URL}"
  log_ok "Gateway API CRDs installed."
fi

# Install Istio with ambient profile
# Set ISTIO_PLATFORM for GKE/EKS/k3d/minikube (e.g. gke, eks, k3d, minikube)
log_info "Installing Istio ambient profile..."
install_args=(--set profile=ambient --skip-confirmation)
[[ -n "${ISTIO_PLATFORM:-}" ]] && install_args+=(--set "global.platform=${ISTIO_PLATFORM}")
"${ISTIOCTL}" install "${install_args[@]}"

log_ok "Istio ambient mode installed."
log_info "Verifying ztunnel DaemonSet..."
kubectl rollout status daemonset/ztunnel -n istio-system --timeout=120s
log_ok "ztunnel is ready."
