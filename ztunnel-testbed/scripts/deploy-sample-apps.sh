#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Deploy sample applications
# =============================================================================
# Deploys http-echo + curl-client to grimlock (ambient) and grimlock-baseline.
# Namespaces configurable via APP_NAMESPACE, APP_NAMESPACE_BASELINE.
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

log_info "Deploying sample applications..."

# Apply ambient label to default namespace (for any existing workloads)
kubectl label namespace default istio.io/dataplane-mode=ambient --overwrite 2>/dev/null || true

# Deploy sample apps (ambient)
kubectl apply -f "${PROJECT_ROOT}/manifests/sample-apps/simple-http-server.yaml"

# Deploy baseline (non-ambient) for performance comparison
kubectl apply -f "${PROJECT_ROOT}/manifests/sample-apps-baseline/http-echo-baseline.yaml"

# Deploy fortio for performance tests
kubectl apply -f "${PROJECT_ROOT}/manifests/performance/fortio-client.yaml" 2>/dev/null || true

log_info "Waiting for sample apps to be ready..."
kubectl rollout status deployment/http-echo -n "${APP_NAMESPACE}" --timeout=120s
kubectl rollout status deployment/curl-client -n "${APP_NAMESPACE}" --timeout=120s
kubectl rollout status deployment/http-echo -n "${APP_NAMESPACE_BASELINE}" --timeout=120s
kubectl rollout status deployment/curl-client -n "${APP_NAMESPACE_BASELINE}" --timeout=120s
kubectl rollout status deployment/fortio -n "${APP_NAMESPACE}" --timeout=60s 2>/dev/null || true

log_ok "Sample apps deployed."
log_info "Pods:"
kubectl get pods -n "${APP_NAMESPACE}" -o wide
