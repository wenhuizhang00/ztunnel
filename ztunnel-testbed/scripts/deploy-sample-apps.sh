#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Deploy sample applications
# =============================================================================
# Deploys sample apps (http-echo + curl-client) with ambient mesh label.
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
kubectl rollout status deployment/http-echo -n sample-apps --timeout=120s
kubectl rollout status deployment/curl-client -n sample-apps --timeout=120s
kubectl rollout status deployment/http-echo -n sample-apps-baseline --timeout=120s
kubectl rollout status deployment/curl-client -n sample-apps-baseline --timeout=120s
kubectl rollout status deployment/fortio -n sample-apps --timeout=60s 2>/dev/null || true

log_ok "Sample apps deployed."
log_info "Pods:"
kubectl get pods -n sample-apps -o wide
