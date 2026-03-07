#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Inspect ztunnel state (workloads, config, logs)
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
[[ -x "$ISTIOCTL" ]] || ISTIOCTL=$(command -v istioctl 2>/dev/null || true)

cmd="${1:-all}"

case "$cmd" in
  workloads)
    log_info "ztunnel workloads (first ztunnel pod)"
    zpod=$(kubectl get pods -n istio-system -l app=ztunnel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [[ -n "$zpod" ]] || { log_error "No ztunnel pod"; exit 1; }
    "$ISTIOCTL" ztunnel-config workloads "$zpod.istio-system" 2>/dev/null || "$ISTIOCTL" x ztunnel-config workloads 2>/dev/null || kubectl exec -n istio-system "$zpod" -- wget -qO- localhost:15000/config_dump 2>/dev/null | head -100
    ;;
  pods)
    log_info "ztunnel pods"
    kubectl get pods -n istio-system -l app=ztunnel -o wide
    ;;
  logs)
    tail="${2:-50}"
    log_info "ztunnel logs (last $tail lines)"
    kubectl logs -n istio-system -l app=ztunnel --tail="$tail"
    ;;
  certificates)
    zpod=$(kubectl get pods -n istio-system -l app=ztunnel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [[ -n "$zpod" ]] || { log_error "No ztunnel pod"; exit 1; }
    log_info "ztunnel certificates"
    "$ISTIOCTL" ztunnel-config certificates "$zpod.istio-system" 2>/dev/null || log_warn "istioctl ztunnel-config certificates not available"
    ;;
  all)
    echo "=== Ztunnel Pods ==="
    kubectl get pods -n istio-system -l app=ztunnel -o wide
    echo ""
    echo "=== Ztunnel Workloads ==="
    zpod=$(kubectl get pods -n istio-system -l app=ztunnel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$zpod" ]] && [[ -x "$ISTIOCTL" ]]; then
      "$ISTIOCTL" ztunnel-config workloads "$zpod.istio-system" 2>/dev/null || true
    fi
    echo ""
    echo "=== Ztunnel Logs (last 20) ==="
    kubectl logs -n istio-system -l app=ztunnel --tail=20 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 {workloads|pods|logs|certificates|all}"
    echo "  workloads   - Show workloads seen by ztunnel"
    echo "  pods       - List ztunnel pods"
    echo "  logs [N]    - Show last N lines of ztunnel logs"
    echo "  certificates - Show TLS certs in ztunnel"
    echo "  all        - Show all of the above"
    exit 1
    ;;
esac
