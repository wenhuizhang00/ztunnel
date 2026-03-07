#!/usr/bin/env bash
# =============================================================================
# Functionality test: Gateway API CRDs installed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Gateway API CRDs"

kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null || fail "CRD gateways.gateway.networking.k8s.io not found"
kubectl get crd httproutes.gateway.networking.k8s.io &>/dev/null || fail "CRD httproutes.gateway.networking.k8s.io not found"

pass "Gateway API CRDs are installed"
