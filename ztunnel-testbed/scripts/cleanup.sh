#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Cleanup (uninstall Istio, remove sample apps)
# =============================================================================
# Does NOT delete the Kubernetes cluster. Use istioctl uninstall for Istio.
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log_info "Cleaning up ztunnel-testbed..."

# Uninstall Istio if istioctl available
ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
if [[ -x "${ISTIOCTL}" ]]; then
  log_info "Uninstalling Istio..."
  "${ISTIOCTL}" uninstall --purge --skip-confirmation 2>/dev/null || true
  log_ok "Istio uninstalled."
fi

# Remove sample apps
log_info "Removing sample apps..."
kubectl delete namespace sample-apps --ignore-not-found --timeout=60s 2>/dev/null || true
kubectl delete namespace sample-apps-baseline --ignore-not-found --timeout=60s 2>/dev/null || true
log_ok "Sample apps removed."

# Optional: remove local cache (istio download, bench results)
if [[ "${REMOVE_CACHE:-}" == "1" ]] || [[ "${REMOVE_CACHE:-}" == "true" ]]; then
  rm -rf "${PROJECT_ROOT}/.cache" "${PROJECT_ROOT}/.bench-results" "${PROJECT_ROOT}/bin"
  log_ok "Cache removed."
else
  read -r -p "Remove local cache (.cache, .bench-results, bin)? [y/N] " resp 2>/dev/null || resp="n"
  if [[ "$resp" =~ ^[yY]$ ]]; then
    rm -rf "${PROJECT_ROOT}/.cache" "${PROJECT_ROOT}/.bench-results" "${PROJECT_ROOT}/bin"
    log_ok "Cache removed."
  fi
fi

log_ok "Cleanup complete."
