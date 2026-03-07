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

"${PROJECT_ROOT}/scripts/create-cluster.sh"
"${PROJECT_ROOT}/scripts/install-istio.sh"
"${PROJECT_ROOT}/scripts/deploy-sample-apps.sh"

log_ok "Setup complete. Run: make test-func"
