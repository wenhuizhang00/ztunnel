#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - One-click setup (cluster + Istio + sample apps)
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log_info "=== ztunnel-testbed: Full setup ==="

"${PROJECT_ROOT}/scripts/create-cluster.sh"
"${PROJECT_ROOT}/scripts/install-istio.sh"
"${PROJECT_ROOT}/scripts/deploy-sample-apps.sh"

log_ok "Setup complete. Run functionality tests: ./scripts/run-functionality-tests.sh"
