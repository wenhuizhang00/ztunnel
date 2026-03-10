#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Setup two-node cross-node test
# =============================================================================
# Sets up fortio-server on the control-plane node (10.200.15.195) and
# fortio-client on the worker node (10.136.0.75) for cross-node ztunnel
# benchmarks.
#
# Architecture:
#   Worker (10.136.0.75):       fortio-client pod
#       |
#       v
#   ztunnel (worker) ──── HBONE mTLS tunnel ──── ztunnel (control-plane)
#       |
#       v
#   Control-plane (10.200.15.195): fortio-server pod
#
# Usage:
#   ./scripts/setup-two-node-test.sh          # deploy cross-node pods
#   ./scripts/setup-two-node-test.sh verify   # verify placement + connectivity
#   ./scripts/setup-two-node-test.sh clean    # remove cross-node pods
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

ACTION="${1:-deploy}"

CP_IP="${CONTROL_PLANE_IP:-10.200.15.195}"
WK_IP="${WORKER_IP:-10.136.0.75}"
NS="${APP_NAMESPACE:-grimlock}"

log_info "Two-node test setup"
log_info "  Control-plane (server): $CP_IP"
log_info "  Worker (client):        $WK_IP"

# Get node names from IPs
CP_NODE=$(kubectl get nodes -o wide --no-headers | grep "$CP_IP" | awk '{print $1}' || true)
WK_NODE=$(kubectl get nodes -o wide --no-headers | grep "$WK_IP" | awk '{print $1}' || true)

if [[ -z "$CP_NODE" ]] || [[ -z "$WK_NODE" ]]; then
  log_error "Could not find both nodes in the cluster."
  echo "  Nodes in cluster:"
  kubectl get nodes -o wide
  echo ""
  echo "  Expected: control-plane at $CP_IP, worker at $WK_IP"
  echo "  Set CONTROL_PLANE_IP and WORKER_IP in config/local.sh"
  exit 1
fi

log_ok "Nodes found: CP=$CP_NODE ($CP_IP), Worker=$WK_NODE ($WK_IP)"

case "$ACTION" in
  deploy)
    log_info "Deploying cross-node test pods..."

    # Ensure namespace exists with ambient label
    kubectl get namespace "$NS" &>/dev/null || kubectl create namespace "$NS"
    kubectl label namespace "$NS" istio.io/dataplane-mode=ambient --overwrite 2>/dev/null || true

    # fortio-server pinned to control-plane
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio-server-cp
  namespace: $NS
  labels:
    app: fortio-server-cp
    test: two-node
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fortio-server-cp
  template:
    metadata:
      labels:
        app: fortio-server-cp
        test: two-node
    spec:
      nodeName: $CP_NODE
      containers:
        - name: fortio
          image: ${FORTIO_IMAGE:-fortio/fortio:latest}
          args: ["server"]
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 500m
              memory: 256Mi
            limits:
              cpu: "2"
              memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: fortio-server-cp
  namespace: $NS
spec:
  selector:
    app: fortio-server-cp
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio-client-wk
  namespace: $NS
  labels:
    app: fortio-client-wk
    test: two-node
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fortio-client-wk
  template:
    metadata:
      labels:
        app: fortio-client-wk
        test: two-node
    spec:
      nodeName: $WK_NODE
      containers:
        - name: fortio
          image: ${FORTIO_IMAGE:-fortio/fortio:latest}
          args: ["server"]
          resources:
            requests:
              cpu: 500m
              memory: 256Mi
            limits:
              cpu: "2"
              memory: 512Mi
EOF

    log_step "ROLLOUT" "Waiting for fortio-server-cp on $CP_NODE..."
    kubectl rollout status deployment/fortio-server-cp -n "$NS" --timeout=120s
    log_step "ROLLOUT" "Waiting for fortio-client-wk on $WK_NODE..."
    kubectl rollout status deployment/fortio-client-wk -n "$NS" --timeout=120s

    echo ""
    log_ok "Cross-node pods deployed:"
    kubectl get pods -n "$NS" -l test=two-node -o wide
    echo ""
    log_info "Run tests:  make bench-two-node"
    log_info "Verify:     $0 verify"
    ;;

  verify)
    log_info "Verifying two-node test setup..."

    # Check pods
    server_pod=$(kubectl get pods -n "$NS" -l app=fortio-server-cp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    client_pod=$(kubectl get pods -n "$NS" -l app=fortio-client-wk -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "$server_pod" ]] || [[ -z "$client_pod" ]]; then
      log_error "Pods not found. Run: $0 deploy"
      exit 1
    fi

    server_node=$(kubectl get pod "$server_pod" -n "$NS" -o jsonpath='{.spec.nodeName}')
    client_node=$(kubectl get pod "$client_pod" -n "$NS" -o jsonpath='{.spec.nodeName}')

    echo ""
    log_info "Pod placement:"
    echo "  fortio-server-cp: $server_pod on $server_node ($CP_IP)"
    echo "  fortio-client-wk: $client_pod on $client_node ($WK_IP)"

    [[ "$server_node" == "$CP_NODE" ]] || log_warn "Server not on control-plane!"
    [[ "$client_node" == "$WK_NODE" ]] || log_warn "Client not on worker!"
    [[ "$server_node" != "$client_node" ]] || log_warn "Both pods on same node (not cross-node)!"

    # Test connectivity
    echo ""
    log_info "Testing connectivity: client ($WK_IP) → server ($CP_IP)..."
    result=$(kubectl exec -n "$NS" "$client_pod" -c fortio -- \
      fortio curl "http://fortio-server-cp.${NS}.svc.cluster.local:8080/" 2>&1 || echo "FAILED")

    if echo "$result" | grep -q "200 OK\|HTTP/1.1 200"; then
      log_ok "Connectivity OK: client on $WK_IP → server on $CP_IP (through ztunnel)"
    else
      log_error "Connectivity failed"
      echo "$result" | tail -5
    fi

    # Check ztunnel sees both pods
    echo ""
    log_info "ztunnel workload enrollment:"
    zt_pod=$(kubectl get pods -n istio-system -l app=ztunnel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$zt_pod" ]]; then
      ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
      [[ -x "$ISTIOCTL" ]] || ISTIOCTL=$(command -v istioctl 2>/dev/null || true)
      if [[ -x "${ISTIOCTL:-}" ]]; then
        "$ISTIOCTL" ztunnel-config workloads 2>/dev/null | grep -E "fortio-server-cp|fortio-client-wk" || echo "  (not found in ztunnel workloads)"
      fi
    fi
    ;;

  clean)
    log_info "Removing two-node test pods..."
    kubectl delete deployment fortio-server-cp fortio-client-wk -n "$NS" --ignore-not-found
    kubectl delete service fortio-server-cp -n "$NS" --ignore-not-found
    log_ok "Cleaned up"
    ;;

  *)
    echo "Usage: $0 [deploy|verify|clean]"
    exit 1
    ;;
esac

exit 0
