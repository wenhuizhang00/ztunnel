#!/usr/bin/env bash
# =============================================================================
# Functionality test: Sample app running
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Sample app running"

# http-echo deployment
ready=$(kubectl get deployment http-echo -n grimlock -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
[[ "${ready:-0}" -ge 1 ]] || fail "http-echo has no ready replicas"

# curl-client deployment
client_ready=$(kubectl get deployment curl-client -n grimlock -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
[[ "${client_ready:-0}" -ge 1 ]] || fail "curl-client has no ready replicas"

pass "Sample apps running (http-echo: $ready, curl-client: $client_ready)"
