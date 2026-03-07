#!/usr/bin/env bash
# =============================================================================
# Functionality test: Ambient vs baseline namespace isolation
# =============================================================================
# Verifies that the ambient mesh is selectively applied: grimlock namespace
# has the ambient label, grimlock-baseline does NOT.
#
# Why this matters:
#   The testbed runs identical apps in two namespaces to compare behavior:
#   - grimlock: ambient mode (traffic goes through ztunnel, mTLS enforced)
#   - grimlock-baseline: no ambient (direct pod networking, no mesh)
#   This test confirms the separation is correct, so performance comparisons
#   and policy tests are valid.
#
# What it checks:
#   1. grimlock has istio.io/dataplane-mode=ambient
#   2. grimlock-baseline does NOT have the ambient label
#   3. Both namespaces have running pods
#
# Skips if: Sample apps not deployed in both namespaces
# Prerequisites: make deploy
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true

NS="${APP_NAMESPACE:-grimlock}"
NS_BASE="${APP_NAMESPACE_BASELINE:-grimlock-baseline}"

test_start "Ambient vs baseline namespace isolation"
test_desc "Checks grimlock=ambient, grimlock-baseline=no-ambient. Validates selective mesh enrollment."

# Verify namespace labels
ambient_label=$(kubectl get namespace "$NS" -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null || true)
baseline_label=$(kubectl get namespace "$NS_BASE" -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null || true)

detail "$NS dataplane-mode: ${ambient_label:-<none>}"
detail "$NS_BASE dataplane-mode: ${baseline_label:-<none>}"

[[ "$ambient_label" == "ambient" ]] || fail "$NS namespace missing istio.io/dataplane-mode=ambient"
[[ "$baseline_label" != "ambient" ]] || fail "$NS_BASE namespace should NOT have ambient label"

# Verify both namespaces have running pods
ambient_pods=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c Running || true)
baseline_pods=$(kubectl get pods -n "$NS_BASE" --no-headers 2>/dev/null | grep -c Running || true)

detail "$NS running pods: $ambient_pods"
detail "$NS_BASE running pods: $baseline_pods"

if [[ "$ambient_pods" -eq 0 ]] || [[ "$baseline_pods" -eq 0 ]]; then
  skip "Need both namespaces deployed (run: make deploy)"
  exit 0
fi

pass "Ambient ($NS: $ambient_pods pods) and baseline ($NS_BASE: $baseline_pods pods) correctly isolated"
