#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Deploy sample applications
# =============================================================================
# Deploys http-echo + curl-client to grimlock (ambient) and grimlock-baseline.
# Uses config/images.sh for HTTP_ECHO_IMAGE, CURL_IMAGE, FORTIO_IMAGE.
# Set USE_LOCAL_IMAGES=1 for local-built images.
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

MANIFEST_CACHE="${PROJECT_ROOT}/.cache/manifests"
mkdir -p "${MANIFEST_CACHE}"

# Substitute images and namespaces in manifest templates
export HTTP_ECHO_IMAGE CURL_IMAGE FORTIO_IMAGE APP_NAMESPACE APP_NAMESPACE_BASELINE
render_manifest() {
  local src="$1"
  local dst="$2"
  envsubst '$HTTP_ECHO_IMAGE,$CURL_IMAGE,$FORTIO_IMAGE,$APP_NAMESPACE,$APP_NAMESPACE_BASELINE' < "$src" > "$dst"
}

log_info "Deploying sample applications (HTTP_ECHO_IMAGE=${HTTP_ECHO_IMAGE})..."

# Apply ambient label to default namespace
kubectl label namespace default istio.io/dataplane-mode=ambient --overwrite 2>/dev/null || true

# Deploy ambient sample apps
log_step "DEPLOY" "Applying ambient sample apps (${APP_NAMESPACE})..."
render_manifest "${PROJECT_ROOT}/manifests/sample-apps/simple-http-server.yaml.template" "${MANIFEST_CACHE}/simple-http-server.yaml"
kubectl apply -f "${MANIFEST_CACHE}/simple-http-server.yaml"

# Deploy baseline
log_step "DEPLOY" "Applying baseline sample apps (${APP_NAMESPACE_BASELINE})..."
render_manifest "${PROJECT_ROOT}/manifests/sample-apps-baseline/http-echo-baseline.yaml.template" "${MANIFEST_CACHE}/http-echo-baseline.yaml"
kubectl apply -f "${MANIFEST_CACHE}/http-echo-baseline.yaml"

# Deploy fortio
log_step "DEPLOY" "Applying fortio (performance tests)..."
render_manifest "${PROJECT_ROOT}/manifests/performance/fortio-client.yaml.template" "${MANIFEST_CACHE}/fortio-client.yaml"
kubectl apply -f "${MANIFEST_CACHE}/fortio-client.yaml" 2>/dev/null || true

# CHOKE: rollout status (image pull + pod scheduling)
log_step "ROLLOUT" "Waiting for http-echo in ${APP_NAMESPACE} (image pull + scheduling, timeout 120s)..."
kubectl rollout status deployment/http-echo -n "${APP_NAMESPACE}" --timeout=120s
log_step "ROLLOUT" "Waiting for curl-client in ${APP_NAMESPACE} (timeout 120s)..."
kubectl rollout status deployment/curl-client -n "${APP_NAMESPACE}" --timeout=120s
log_step "ROLLOUT" "Waiting for http-echo + curl-client in ${APP_NAMESPACE_BASELINE} (timeout 120s each)..."
kubectl rollout status deployment/http-echo -n "${APP_NAMESPACE_BASELINE}" --timeout=120s
kubectl rollout status deployment/curl-client -n "${APP_NAMESPACE_BASELINE}" --timeout=120s
log_step "ROLLOUT" "Waiting for fortio in ${APP_NAMESPACE} (timeout 60s)..."
kubectl rollout status deployment/fortio -n "${APP_NAMESPACE}" --timeout=60s 2>/dev/null || true

log_step_ok "DEPLOY" "Sample apps ready"
log_info "Pods:"
kubectl get pods -n "${APP_NAMESPACE}" -o wide
