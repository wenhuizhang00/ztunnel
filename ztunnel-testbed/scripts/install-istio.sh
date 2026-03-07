#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Install Istio ambient mode
# =============================================================================
# 1. Download istioctl if needed
# 2. Install Gateway API CRDs
# 3. Install Istio with ambient profile (set ISTIO_PLATFORM for gke/eks/k3d/minikube)
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

log_info "Installing Istio ambient mode (version: ${ISTIO_VERSION})"

# Detect OS and arch
case "$(uname -s)" in
  Darwin) TARGET_OS=osx ;;
  Linux)  TARGET_OS=linux ;;
  *) TARGET_OS=linux ;;
esac
case "$(uname -m)" in
  x86_64)  TARGET_ARCH=amd64 ;;
  arm64|aarch64) TARGET_ARCH=arm64 ;;
  *) TARGET_ARCH=amd64 ;;
esac

# CHOKE: istioctl download (network - may be slow behind proxy)
ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
if [[ ! -x "${ISTIOCTL}" ]] || [[ ! -d "${PROJECT_ROOT}/.cache/istio-${ISTIO_VERSION}" ]]; then
  log_step "ISTIOCTL" "Downloading Istio ${ISTIO_VERSION} (network - may take 1-3 min)..."
  istio_dl_start=$(date +%s)
  mkdir -p "${PROJECT_ROOT}/.cache" "${PROJECT_ROOT}/bin"

  ISTIO_TARBALL="${PROJECT_ROOT}/.cache/istio-${ISTIO_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
  if [[ ! -f "$ISTIO_TARBALL" ]]; then
    ISTIO_DL_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
    log_info "Fetching ${ISTIO_DL_URL}"
    curl -sL --fail -o "$ISTIO_TARBALL" "$ISTIO_DL_URL" || {
      log_error "Failed to download Istio ${ISTIO_VERSION} from GitHub. Check version and network."
      rm -f "$ISTIO_TARBALL"
      exit 1
    }
  fi

  if [[ ! -d "${PROJECT_ROOT}/.cache/istio-${ISTIO_VERSION}" ]]; then
    tar xzf "$ISTIO_TARBALL" -C "${PROJECT_ROOT}/.cache"
  fi

  cp -f "${PROJECT_ROOT}/.cache/istio-${ISTIO_VERSION}/bin/istioctl" "${ISTIOCTL}"
  chmod +x "${ISTIOCTL}"
  log_step_ok "ISTIOCTL" "Istio downloaded" "$(( $(date +%s) - istio_dl_start ))s"
fi
log_ok "istioctl: $(${ISTIOCTL} version --short 2>/dev/null || ${ISTIOCTL} version 2>/dev/null | head -1)"

# CHOKE: Gateway API CRDs (network fetch)
log_step "GATEWAY-API" "Installing Gateway API CRDs (${GATEWAY_API_VERSION}) - fetching from network..."
if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
  log_step_ok "GATEWAY-API" "CRDs already installed"
else
  kubectl apply --server-side -f "${GATEWAY_API_INSTALL_URL}"
  log_step_ok "GATEWAY-API" "CRDs installed"
fi

# CHOKE: Istio install (pulls images, applies manifests)
log_step "ISTIO" "Installing Istio ambient profile (pulling images - may take 2-5 min)..."
istio_install_start=$(date +%s)
install_args=(--set profile=ambient --skip-confirmation)
[[ -n "${ISTIO_PLATFORM:-}" ]] && install_args+=(--set "global.platform=${ISTIO_PLATFORM}")
"${ISTIOCTL}" install "${install_args[@]}"
log_step_ok "ISTIO" "Istio installed" "$(( $(date +%s) - istio_install_start ))s"

# CHOKE: ztunnel DaemonSet rollout
log_step "ZTUNNEL" "Waiting for ztunnel DaemonSet rollout (timeout 120s)..."
kubectl rollout status daemonset/ztunnel -n istio-system --timeout=120s
log_step_ok "ZTUNNEL" "ztunnel is ready"
