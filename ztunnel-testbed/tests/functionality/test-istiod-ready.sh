#!/usr/bin/env bash
# =============================================================================
# Functionality test: Istiod ready
# =============================================================================
# Verifies that the Istiod control plane is running with at least 1 ready
# replica.
#
# Why this matters:
#   Istiod is the Istio control plane. It pushes xDS configuration to ztunnel,
#   manages certificates (mTLS), and handles service discovery. Without a
#   healthy istiod, ztunnel cannot get its configuration and new workloads
#   won't receive certificates.
#
# What it checks:
#   1. istiod Deployment exists in istio-system
#   2. At least 1 replica has Ready status
#   3. Reports the image version for quick verification
#
# Prerequisites: Istio installed (make install)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Istiod ready"

kubectl get deployment istiod -n istio-system &>/dev/null || fail "istiod deployment not found"
ready=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
version=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | awk -F: '{print $NF}')
detail "istiod replicas: ${ready:-0}, image: ${version:-unknown}"

[[ "${ready:-0}" -ge 1 ]] || fail "istiod has no ready replicas"
pass "Istiod is ready (${ready} replica(s), ${version})"
