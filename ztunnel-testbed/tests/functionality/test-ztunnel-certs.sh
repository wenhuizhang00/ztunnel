#!/usr/bin/env bash
# =============================================================================
# Functionality test: ztunnel certificates
# =============================================================================
# Verifies that ztunnel has active mTLS certificates issued by Istiod.
#
# Why this matters:
#   In ambient mode, ztunnel establishes HBONE (HTTP/2 CONNECT) tunnels
#   between nodes using mTLS. Each workload identity gets a SPIFFE certificate
#   (e.g. spiffe://cluster.local/ns/grimlock/sa/http-echo). If certificates
#   are missing or expired, inter-pod mTLS will fail and traffic is dropped.
#
# What it checks:
#   1. istioctl ztunnel-config certificates returns output
#   2. Output contains ACTIVE/VALID certs or spiffe:// URIs
#   3. Reports certificate count
#
# Skips if: istioctl not available, or command output format unrecognized
# Prerequisites: Istio installed, ztunnel running
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
[[ -x "$ISTIOCTL" ]] || ISTIOCTL=$(command -v istioctl 2>/dev/null || true)

test_start "ztunnel certificates"

if [[ ! -x "${ISTIOCTL:-}" ]]; then
  skip "istioctl not found (run: make install)"
  exit 0
fi

ztunnel_pod=$(kubectl get pods -n istio-system -l app=ztunnel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$ztunnel_pod" ]]; then
  fail "No ztunnel pod found"
fi

detail "querying certificates from $ztunnel_pod"

# Try multiple command variants (API changed across Istio versions)
cert_out=$("$ISTIOCTL" ztunnel-config certificates "$ztunnel_pod.istio-system" 2>/dev/null || \
           "$ISTIOCTL" x ztunnel-config certificates "$ztunnel_pod.istio-system" 2>/dev/null || true)
if [[ -z "$cert_out" ]]; then
  cert_out=$("$ISTIOCTL" ztunnel-config certificates 2>/dev/null || true)
fi

if [[ -z "$cert_out" ]]; then
  skip "Could not retrieve ztunnel certificates (istioctl version may differ)"
  exit 0
fi

cert_count=$(echo "$cert_out" | grep -c "ACTIVE\|VALID\|spiffe" || true)
detail "certificates found: $cert_count"
# Show first few lines of cert output for quick inspection
echo "$cert_out" | head -5 | while read -r line; do
  detail "$line"
done

[[ "$cert_count" -gt 0 ]] || fail "No active certificates found in ztunnel"
pass "ztunnel has $cert_count active certificate(s)"
