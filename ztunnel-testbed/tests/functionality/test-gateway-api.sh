#!/usr/bin/env bash
# =============================================================================
# Functionality test: Gateway API CRDs installed
# =============================================================================
# Verifies that Kubernetes Gateway API Custom Resource Definitions are present.
#
# Why this matters:
#   Istio ambient mode uses Gateway API for traffic routing (HTTPRoute,
#   Gateway, etc.). Without these CRDs, you cannot define routes, and
#   istioctl may fail to configure traffic policies.
#
# What it checks:
#   1. gateways.gateway.networking.k8s.io CRD exists
#   2. httproutes.gateway.networking.k8s.io CRD exists
#
# Prerequisites: Gateway API CRDs installed (part of make install)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Gateway API CRDs"
test_desc "Checks Gateway/HTTPRoute CRDs exist. Required for Istio traffic routing."

kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null || fail "CRD gateways.gateway.networking.k8s.io not found"
kubectl get crd httproutes.gateway.networking.k8s.io &>/dev/null || fail "CRD httproutes.gateway.networking.k8s.io not found"

detail "gateways.gateway.networking.k8s.io: present"
detail "httproutes.gateway.networking.k8s.io: present"

pass "Gateway API CRDs are installed"
