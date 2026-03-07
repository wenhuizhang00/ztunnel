#!/usr/bin/env bash
# =============================================================================
# Functionality test: Namespace ambient label
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Namespace ambient label"

# grimlock namespace should have ambient label
label=$(kubectl get namespace grimlock -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null || true)
[[ "$label" == "ambient" ]] || fail "grimlock namespace missing istio.io/dataplane-mode=ambient (got: ${label})"

pass "grimlock has istio.io/dataplane-mode=ambient"
