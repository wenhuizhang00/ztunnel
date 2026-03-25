#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Install Cilium CNI (no Helm, uses Cilium CLI)
# =============================================================================
# Compatible with Istio ambient mode:
#   - cni.exclusive=false (Istio CNI chaining)
#   - socketLB.hostNamespaceOnly=true (avoid intercepting ztunnel traffic)
#   - kubeProxyReplacement=false (recommended)
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

# Load POD_NETWORK_CIDR for flat network (used by config/cilium.sh)
source "${PROJECT_ROOT}/config/baremetal.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/config/cilium.sh" 2>/dev/null || true

log_info "Installing Cilium (${CILIUM_VERSION}) - Istio ambient compatible (flat network, no Helm)"

# CHOKE: Cilium CLI download (network)
CILIUM_CLI="${PROJECT_ROOT}/bin/cilium"
if [[ ! -x "${CILIUM_CLI}" ]]; then
  log_step "CILIUM-CLI" "Downloading Cilium CLI (network - may be slow behind proxy)..."
  CILIUM_CLI_VERSION=$(curl -sL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt 2>/dev/null || echo "v0.18.7")
  CLI_ARCH=amd64
  [[ "$(uname -m)" == "aarch64" ]] || [[ "$(uname -m)" == "arm64" ]] && CLI_ARCH=arm64
  mkdir -p "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/.cache"
  cd "${PROJECT_ROOT}/.cache"
  curl -sL --fail -o cilium-cli.tar.gz "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-$(uname -s | tr '[:upper:]' '[:lower:]')-${CLI_ARCH}.tar.gz" || true
  if [[ -f cilium-cli.tar.gz ]]; then
    tar xzf cilium-cli.tar.gz -C "${PROJECT_ROOT}/bin"
    chmod +x "${PROJECT_ROOT}/bin/cilium"
  else
    log_error "Failed to download Cilium CLI. Install manually: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/"
    exit 1
  fi
  log_step_ok "CILIUM-CLI" "Cilium CLI downloaded"
  cd "${PROJECT_ROOT}"
fi

check_cmd kubectl

# Warn if another CNI exists (not Cilium)
if kubectl get ds -n kube-system weave-net &>/dev/null || kubectl get ds -n kube-system flannel &>/dev/null; then
  log_warn "Existing CNI detected. Remove it before installing Cilium."
fi

# CHOKE: Cilium install (pulls images, --wait)
log_step "CILIUM" "Installing Cilium (pulling images + --wait - may take 2-5 min)..."
cilium_install_start=$(date +%s)
CILIUM_SET_ARGS=(
  --version "v${CILIUM_VERSION}"
  --set cni.exclusive=false
  --set socketLB.hostNamespaceOnly=true
  --set kubeProxyReplacement=false
)
if [[ "${CILIUM_FLAT_NETWORK:-true}" == "true" ]] && [[ -n "${CILIUM_NATIVE_ROUTING_CIDR:-}" ]]; then
  CILIUM_SET_ARGS+=(--set "tunnel=disabled" --set "ipv4NativeRoutingCIDR=${CILIUM_NATIVE_ROUTING_CIDR}")
  log_info "Flat network: tunnel=disabled, ipv4NativeRoutingCIDR=${CILIUM_NATIVE_ROUTING_CIDR}"
fi
"${CILIUM_CLI}" install "${CILIUM_SET_ARGS[@]}" --wait

log_step_ok "CILIUM" "Cilium installed" "$(( $(date +%s) - cilium_install_start ))s"
log_info "Verify: kubectl get configmaps -n kube-system cilium-config -oyaml | grep -E 'tunnel|cni-exclusive|bpf-lb-sock'"
