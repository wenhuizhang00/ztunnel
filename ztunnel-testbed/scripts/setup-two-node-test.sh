#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Setup two-node cross-node test
# =============================================================================
# Deploys fortio pods pinned to specific nodes for cross-node ztunnel testing.
#
# Architecture:
#   Worker:          fortio-client-wk pod (load generator)
#       |
#       v
#   ztunnel (worker) ──── HBONE mTLS tunnel ──── ztunnel (control-plane)
#       |
#       v
#   Control-plane:   fortio-server-cp pod (target server)
#
# Also deploys a same-node server for baseline comparison:
#   Worker:          fortio-client-wk → fortio-server-wk (same node, no HBONE)
#
# Usage:
#   ./scripts/setup-two-node-test.sh          # deploy cross-node pods
#   ./scripts/setup-two-node-test.sh verify   # verify placement + connectivity + mTLS
#   ./scripts/setup-two-node-test.sh clean    # remove cross-node pods
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

ACTION="${1:-deploy}"
NS="${APP_NAMESPACE:-grimlock}"

# Auto-detect node IPs from cluster
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
CP_IP=$(kubectl get node "$CP_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)

# Worker = first non-control-plane node
WK_NODE=$(kubectl get nodes --no-headers | grep -v control-plane | awk '{print $1}' | head -1 || true)
WK_IP=$(kubectl get node "$WK_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)

# Allow override from config
CP_IP="${CONTROL_PLANE_IP:-$CP_IP}"
WK_IP="${WORKER_IP:-$WK_IP}"

log_info "Two-node test setup"
log_info "  Control-plane: $CP_NODE ($CP_IP)"
log_info "  Worker:        $WK_NODE ($WK_IP)"

if [[ -z "$CP_NODE" ]] || [[ -z "$WK_NODE" ]]; then
  log_error "Need at least 2 nodes in the cluster."
  kubectl get nodes -o wide
  exit 1
fi

if [[ "$CP_NODE" == "$WK_NODE" ]]; then
  log_error "Control-plane and worker are the same node. Need 2 separate nodes."
  exit 1
fi

case "$ACTION" in
  deploy)
    log_info "Deploying two-node test pods..."

    kubectl get namespace "$NS" &>/dev/null || kubectl create namespace "$NS"
    kubectl label namespace "$NS" istio.io/dataplane-mode=ambient --overwrite 2>/dev/null || true

    cat <<EOF | kubectl apply -f -
# --- Server on control-plane (cross-node target) ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio-server-cp
  namespace: $NS
  labels: {app: fortio-server-cp, test: two-node}
spec:
  replicas: 1
  selector: {matchLabels: {app: fortio-server-cp}}
  template:
    metadata:
      labels: {app: fortio-server-cp, test: two-node, topology: control-plane}
    spec:
      nodeName: $CP_NODE
      containers:
        - name: fortio
          image: ${FORTIO_IMAGE:-fortio/fortio:latest}
          args: ["server"]
          ports: [{containerPort: 8080}]
          resources:
            requests: {cpu: 500m, memory: 256Mi}
            limits: {cpu: "2", memory: 512Mi}
---
apiVersion: v1
kind: Service
metadata:
  name: fortio-server-cp
  namespace: $NS
spec:
  selector: {app: fortio-server-cp}
  ports: [{port: 8080, targetPort: 8080}]
---
# --- Server on worker (same-node baseline) ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio-server-wk
  namespace: $NS
  labels: {app: fortio-server-wk, test: two-node}
spec:
  replicas: 1
  selector: {matchLabels: {app: fortio-server-wk}}
  template:
    metadata:
      labels: {app: fortio-server-wk, test: two-node, topology: worker}
    spec:
      nodeName: $WK_NODE
      containers:
        - name: fortio
          image: ${FORTIO_IMAGE:-fortio/fortio:latest}
          args: ["server"]
          ports: [{containerPort: 8080}]
          resources:
            requests: {cpu: 500m, memory: 256Mi}
            limits: {cpu: "2", memory: 512Mi}
---
apiVersion: v1
kind: Service
metadata:
  name: fortio-server-wk
  namespace: $NS
spec:
  selector: {app: fortio-server-wk}
  ports: [{port: 8080, targetPort: 8080}]
---
# --- Client on worker ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio-client-wk
  namespace: $NS
  labels: {app: fortio-client-wk, test: two-node}
spec:
  replicas: 1
  selector: {matchLabels: {app: fortio-client-wk}}
  template:
    metadata:
      labels: {app: fortio-client-wk, test: two-node, topology: worker}
    spec:
      nodeName: $WK_NODE
      containers:
        - name: fortio
          image: ${FORTIO_IMAGE:-fortio/fortio:latest}
          args: ["server"]
          resources:
            requests: {cpu: 500m, memory: 256Mi}
            limits: {cpu: "2", memory: 512Mi}
---
# --- Client on control-plane (for reverse direction) ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio-client-cp
  namespace: $NS
  labels: {app: fortio-client-cp, test: two-node}
spec:
  replicas: 1
  selector: {matchLabels: {app: fortio-client-cp}}
  template:
    metadata:
      labels: {app: fortio-client-cp, test: two-node, topology: control-plane}
    spec:
      nodeName: $CP_NODE
      containers:
        - name: fortio
          image: ${FORTIO_IMAGE:-fortio/fortio:latest}
          args: ["server"]
          resources:
            requests: {cpu: 500m, memory: 256Mi}
            limits: {cpu: "2", memory: 512Mi}
EOF

    log_step "ROLLOUT" "Waiting for pods..."
    kubectl rollout status deployment/fortio-server-cp -n "$NS" --timeout=120s
    kubectl rollout status deployment/fortio-server-wk -n "$NS" --timeout=120s
    kubectl rollout status deployment/fortio-client-wk -n "$NS" --timeout=120s
    kubectl rollout status deployment/fortio-client-cp -n "$NS" --timeout=120s

    echo ""
    log_ok "Two-node pods deployed:"
    kubectl get pods -n "$NS" -l test=two-node -o wide
    echo ""
    echo "  Test paths available:"
    echo "    Cross-node:  fortio-client-wk ($WK_NODE) → fortio-server-cp ($CP_NODE)"
    echo "    Reverse:     fortio-client-cp ($CP_NODE) → fortio-server-wk ($WK_NODE)"
    echo "    Same-node:   fortio-client-wk ($WK_NODE) → fortio-server-wk ($WK_NODE)"
    echo ""
    log_info "Run: make verify-two-node   then: make bench-two-node"
    ;;

  verify)
    log_info "Verifying two-node test setup..."

    # Pod discovery
    svr_cp=$(kubectl get pods -n "$NS" -l app=fortio-server-cp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    svr_wk=$(kubectl get pods -n "$NS" -l app=fortio-server-wk -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    cli_wk=$(kubectl get pods -n "$NS" -l app=fortio-client-wk -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    cli_cp=$(kubectl get pods -n "$NS" -l app=fortio-client-cp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "$svr_cp" ]] || [[ -z "$cli_wk" ]]; then
      log_error "Pods not found. Run: make setup-two-node"
      exit 1
    fi

    echo ""
    log_info "1. Pod placement:"
    printf "  %-20s  %-40s  %s\n" "Role" "Pod" "Node"
    printf "  %-20s  %-40s  %s\n" "----" "---" "----"
    for pod_label in fortio-server-cp fortio-server-wk fortio-client-wk fortio-client-cp; do
      pod=$(kubectl get pods -n "$NS" -l app=$pod_label -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "N/A")
      node=$(kubectl get pod "$pod" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "N/A")
      printf "  %-20s  %-40s  %s\n" "$pod_label" "$pod" "$node"
    done

    svr_cp_node=$(kubectl get pod "$svr_cp" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    cli_wk_node=$(kubectl get pod "$cli_wk" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    [[ "$svr_cp_node" != "$cli_wk_node" ]] && log_ok "Cross-node: client and server on different nodes" || log_warn "NOT cross-node!"

    # Connectivity tests
    echo ""
    log_info "2. Connectivity (cross-node: worker → control-plane):"
    r1=$(kubectl exec -n "$NS" "$cli_wk" -c fortio -- fortio curl "http://fortio-server-cp.${NS}.svc.cluster.local:8080/" 2>&1 || echo "FAILED")
    echo "$r1" | grep -q "200 OK\|HTTP/1.1 200" && log_ok "  worker → control-plane: OK" || log_error "  worker → control-plane: FAILED"

    if [[ -n "$cli_cp" ]] && [[ -n "$svr_wk" ]]; then
      echo ""
      log_info "3. Connectivity (reverse: control-plane → worker):"
      r2=$(kubectl exec -n "$NS" "$cli_cp" -c fortio -- fortio curl "http://fortio-server-wk.${NS}.svc.cluster.local:8080/" 2>&1 || echo "FAILED")
      echo "$r2" | grep -q "200 OK\|HTTP/1.1 200" && log_ok "  control-plane → worker: OK" || log_error "  control-plane → worker: FAILED"
    fi

    echo ""
    log_info "4. Connectivity (same-node baseline: worker → worker):"
    r3=$(kubectl exec -n "$NS" "$cli_wk" -c fortio -- fortio curl "http://fortio-server-wk.${NS}.svc.cluster.local:8080/" 2>&1 || echo "FAILED")
    echo "$r3" | grep -q "200 OK\|HTTP/1.1 200" && log_ok "  worker → worker (same-node): OK" || log_error "  worker → worker: FAILED"

    # mTLS verification
    echo ""
    log_info "5. ztunnel mTLS enrollment:"
    ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
    [[ -x "$ISTIOCTL" ]] || ISTIOCTL=$(command -v istioctl 2>/dev/null || true)
    if [[ -x "${ISTIOCTL:-}" ]]; then
      "$ISTIOCTL" ztunnel-config workloads 2>/dev/null | grep -E "fortio-server-cp|fortio-client-wk|fortio-server-wk|fortio-client-cp" | head -6 || echo "  (not found in workloads)"
      echo ""
      certs=$("$ISTIOCTL" ztunnel-config certificates 2>/dev/null | grep -c "ns/$NS" || true)
      log_info "  SPIFFE certificates for $NS: $certs"
    fi

    echo ""
    log_ok "Verification complete"
    ;;

  clean)
    log_info "Removing two-node test pods..."
    kubectl delete deployment fortio-server-cp fortio-server-wk fortio-client-wk fortio-client-cp -n "$NS" --ignore-not-found 2>/dev/null || true
    kubectl delete service fortio-server-cp fortio-server-wk -n "$NS" --ignore-not-found 2>/dev/null || true
    log_ok "Cleaned up"
    ;;

  *)
    echo "Usage: $0 [deploy|verify|clean]"
    exit 1
    ;;
esac

exit 0
