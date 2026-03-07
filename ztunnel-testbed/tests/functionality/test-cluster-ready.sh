#!/usr/bin/env bash
# =============================================================================
# Functionality test: Cluster ready
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Cluster ready"

# All nodes Ready
nodes_ready=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | tr ' ' '\n' | grep -c True || true)
nodes_total=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
[[ "$nodes_ready" -eq "$nodes_total" ]] || fail "Not all nodes Ready: $nodes_ready/$nodes_total"

pass "All $nodes_total nodes are Ready"
