#!/usr/bin/env bash
# =============================================================================
# Functionality test: Sample app running
# =============================================================================
# Verifies that the http-echo and curl-client deployments have ready pods.
#
# Why this matters:
#   These are the sample workloads used for connectivity tests. http-echo
#   returns a known response when curled; curl-client provides a shell to
#   execute requests from inside the mesh. If either is not running, the
#   pod-to-pod, pod-to-service, and DNS tests will fail.
#
# What it checks:
#   1. http-echo deployment in grimlock has >= 1 ready replica
#   2. curl-client deployment in grimlock has >= 1 ready replica
#
# Prerequisites: make deploy
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true

NS="${APP_NAMESPACE:-grimlock}"

test_start "Sample app running"
test_desc "Checks http-echo and curl-client deployments are ready. These are needed for connectivity tests."

# http-echo deployment
ready=$(kubectl get deployment http-echo -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
detail "http-echo ready replicas: ${ready:-0}"
[[ "${ready:-0}" -ge 1 ]] || fail "http-echo has no ready replicas in $NS"

# curl-client deployment
client_ready=$(kubectl get deployment curl-client -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
detail "curl-client ready replicas: ${client_ready:-0}"
[[ "${client_ready:-0}" -ge 1 ]] || fail "curl-client has no ready replicas in $NS"

pass "Sample apps running (http-echo: $ready, curl-client: $client_ready)"
