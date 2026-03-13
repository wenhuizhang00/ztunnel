#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Cilium Configuration
# =============================================================================
# Used by install-cilium.sh and create-cluster-baremetal.sh. Istio ambient compatible.
# Flat network: tunnel=disabled, ipv4NativeRoutingCIDR for direct routing (no VXLAN).
# =============================================================================

# Cilium version (e.g. 1.16.0, 1.19.1)
export CILIUM_VERSION="${CILIUM_VERSION:-1.16.0}"

# Flat network: direct routing, no encapsulation. Uses POD_NETWORK_CIDR from baremetal.sh.
# Set to empty to use Cilium default (tunnel mode).
export CILIUM_FLAT_NETWORK="${CILIUM_FLAT_NETWORK:-true}"
export CILIUM_NATIVE_ROUTING_CIDR="${CILIUM_NATIVE_ROUTING_CIDR:-${POD_NETWORK_CIDR:-192.168.0.0/16}}"
