#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Cleanup
# =============================================================================
# Interactive cleanup with selectable levels:
#   1) Apps only     - Remove sample apps (namespaces grimlock, grimlock-baseline)
#   2) Apps + Istio  - Uninstall Istio ambient, Gateway API CRDs, sample apps
#   3) Full cleanup  - All above + local cache, bin, bench results
#   4) Nuclear       - All above + destroy the Kubernetes cluster (kubeadm reset)
#
# Non-interactive:
#   CLEAN=apps make clean
#   CLEAN=istio make clean
#   CLEAN=full make clean
#   CLEAN=nuclear make clean
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

CLEAN="${CLEAN:-${1:-}}"

# Interactive menu
if [[ -z "$CLEAN" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
  echo ""
  echo -e "${BLUE}Cleanup${NC}"
  echo "─────────────────────────────────────────"
  echo ""
  echo "  1) Apps only      - Remove sample apps (namespaces, deployments)"
  echo "  2) Apps + Istio   - Uninstall Istio + Gateway API CRDs + sample apps"
  echo "  3) Full cleanup   - All above + local cache (.cache, bin, .bench-results)"
  echo "  4) Nuclear        - All above + destroy Kubernetes cluster (kubeadm reset)"
  echo ""
  echo "  0) Cancel"
  echo ""
  read -rp "Select cleanup level [0-4]: " selection
  case "$selection" in
    1) CLEAN=apps ;;
    2) CLEAN=istio ;;
    3) CLEAN=full ;;
    4) CLEAN=nuclear ;;
    0|"") log_info "Cancelled."; exit 0 ;;
    *) log_error "Invalid selection"; exit 1 ;;
  esac
fi

CLEAN="${CLEAN:-apps}"

log_info "Cleanup level: $CLEAN"

# ─── Level 1: Remove sample apps ───
clean_apps() {
  log_info "Removing sample apps..."

  # Delete ambient namespace (grimlock)
  if kubectl get namespace "${APP_NAMESPACE}" &>/dev/null; then
    kubectl delete namespace "${APP_NAMESPACE}" --ignore-not-found --timeout=60s 2>/dev/null || true
    log_ok "Namespace ${APP_NAMESPACE} deleted"
  fi

  # Delete baseline namespace (grimlock-baseline)
  if kubectl get namespace "${APP_NAMESPACE_BASELINE}" &>/dev/null; then
    kubectl delete namespace "${APP_NAMESPACE_BASELINE}" --ignore-not-found --timeout=60s 2>/dev/null || true
    log_ok "Namespace ${APP_NAMESPACE_BASELINE} deleted"
  fi

  # Remove ambient label from default namespace
  kubectl label namespace default istio.io/dataplane-mode- 2>/dev/null || true

  # Clean rendered manifests
  rm -rf "${PROJECT_ROOT}/.cache/manifests" 2>/dev/null || true

  log_ok "Sample apps removed"
}

# ─── Level 2: Uninstall Istio ───
clean_istio() {
  clean_apps

  ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
  [[ -x "$ISTIOCTL" ]] || ISTIOCTL=$(command -v istioctl 2>/dev/null || true)

  if [[ -x "${ISTIOCTL:-}" ]]; then
    log_info "Uninstalling Istio (purge)..."
    "${ISTIOCTL}" uninstall --purge --skip-confirmation 2>/dev/null || true
    log_ok "Istio uninstalled"
  else
    log_info "istioctl not found, removing Istio namespace manually..."
    kubectl delete namespace istio-system --ignore-not-found --timeout=120s 2>/dev/null || true
  fi

  # Remove Gateway API CRDs
  log_info "Removing Gateway API CRDs..."
  kubectl delete crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io \
    grpcroutes.gateway.networking.k8s.io tcproutes.gateway.networking.k8s.io \
    tlsroutes.gateway.networking.k8s.io udproutes.gateway.networking.k8s.io \
    referencegrants.gateway.networking.k8s.io backendtlspolicies.gateway.networking.k8s.io \
    2>/dev/null || true
  # Also try the x-k8s experimental CRDs
  kubectl delete crd xbackendtrafficpolicies.gateway.networking.x-k8s.io \
    xlistenersets.gateway.networking.x-k8s.io xmeshes.gateway.networking.x-k8s.io \
    2>/dev/null || true
  log_ok "Gateway API CRDs removed"

  log_ok "Istio + CRDs cleaned"
}

# ─── Level 3: Full cleanup (local files) ───
clean_full() {
  clean_istio

  log_info "Removing local cache and binaries..."
  rm -rf "${PROJECT_ROOT}/.cache"
  rm -rf "${PROJECT_ROOT}/.bench-results"
  rm -rf "${PROJECT_ROOT}/bin"
  log_ok "Local cache removed (.cache, .bench-results, bin)"

  log_ok "Full cleanup complete"
}

# ─── Level 4: Nuclear (destroy cluster) ───
clean_nuclear() {
  clean_full

  echo ""
  log_warn "NUCLEAR: This will destroy the Kubernetes cluster (kubeadm reset)."
  if [[ -t 0 ]] && [[ -t 1 ]]; then
    read -rp "Are you sure? Type 'yes' to confirm: " confirm
    [[ "$confirm" == "yes" ]] || { log_info "Cancelled."; return; }
  fi

  log_info "Destroying Kubernetes cluster..."

  # Reset kubeadm on this node
  sudo kubeadm reset -f 2>/dev/null || true
  sudo rm -rf /etc/cni/net.d/* 2>/dev/null || true

  # Remove kubeconfig
  rm -f "$HOME/.kube/config" 2>/dev/null || true
  sudo rm -f /root/.kube/config 2>/dev/null || true

  # Remove kubectl wrapper
  if [[ -f /usr/local/bin/.kubectl-wrapper ]]; then
    sudo rm -f /usr/local/bin/kubectl /usr/local/bin/.kubectl-wrapper 2>/dev/null || true
    log_ok "kubectl wrapper removed"
  fi

  # Remove sudoers drop-in
  sudo rm -f /etc/sudoers.d/99-k8s-proxy-env 2>/dev/null || true

  # Remove bashrc additions
  if grep -q "ztunnel-testbed" "$HOME/.bashrc" 2>/dev/null; then
    sed -i '/# Added by ztunnel-testbed/,+3d' "$HOME/.bashrc" 2>/dev/null || true
    log_ok "Removed ztunnel-testbed entries from ~/.bashrc"
  fi

  # Restart containerd to clean state
  sudo systemctl restart containerd 2>/dev/null || true

  log_ok "Cluster destroyed. To recreate: make create-baremetal"
}

# Execute the selected level
case "$CLEAN" in
  apps)    clean_apps ;;
  istio)   clean_istio ;;
  full)    clean_full ;;
  nuclear) clean_nuclear ;;
  *)       log_error "Unknown level: $CLEAN (use: apps, istio, full, nuclear)"; exit 1 ;;
esac

echo ""
log_ok "Cleanup complete ($CLEAN)"
