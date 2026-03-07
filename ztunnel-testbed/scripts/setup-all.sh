#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - One-click setup
# =============================================================================
# 1. Verify cluster connectivity (create-cluster.sh does NOT create a cluster)
# 2. Install Istio ambient
# 3. Deploy sample apps
# Requires: existing cluster, kubectl configured
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log_info "=== ztunnel-testbed: Full setup ==="
echo ""

log_info "Step 1/3: Verify cluster connectivity..."
"${PROJECT_ROOT}/scripts/create-cluster.sh"
log_ok "Step 1/3 OK"
echo ""

log_info "Step 2/3: Install Istio ambient..."
"${PROJECT_ROOT}/scripts/install-istio.sh"
log_ok "Step 2/3 OK"
echo ""

log_info "Step 3/3: Deploy sample apps..."
"${PROJECT_ROOT}/scripts/deploy-sample-apps.sh"
log_ok "Step 3/3 OK"
echo ""

log_ok "Setup complete. Run: make test-func"
