#!/usr/bin/env bash
# =============================================================================
# Functionality test: Cluster ready
# =============================================================================
# Verifies that ALL Kubernetes nodes report Ready status.
#
# Why this matters:
#   A NotReady node means kubelet cannot schedule pods on it. Common causes:
#   - CNI plugin not initialized (containerd inotify watch lost)
#   - kubelet cannot reach the API server
#   - Node resource pressure (memory, disk, PID)
#
# What it checks:
#   1. Counts nodes with condition Ready=True
#   2. Compares to total node count
#   3. Shows each node's status line for quick diagnosis
#
# Prerequisites: kubectl connected to cluster
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Cluster ready"

# Query the Ready condition for every node
nodes_ready=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | tr ' ' '\n' | grep -c True || true)
nodes_total=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')

detail "Nodes: $nodes_ready/$nodes_total ready"

# Show each node for quick visual inspection
kubectl get nodes --no-headers | while read -r line; do
  detail "$line"
done

[[ "$nodes_ready" -eq "$nodes_total" ]] || fail "Not all nodes Ready: $nodes_ready/$nodes_total"
pass "All $nodes_total nodes are Ready"
