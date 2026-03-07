#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Bare Metal Kubernetes Configuration
# =============================================================================
# For kubeadm-based cluster on bare metal. Not k3s.
# =============================================================================

# Control-plane node IP or hostname (for kubeadm join --control-plane)
export CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-}"

# Pod network CIDR (must not overlap with node networks)
# 192.168.0.0/16 matches Calico default
export POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-192.168.0.0/16}"

# Kubernetes version for kubeadm (e.g. 1.30.0)
export K8S_VERSION="${K8S_VERSION:-1.30.0}"

# CNI provider: calico | cilium
export CNI_PROVIDER="${CNI_PROVIDER:-calico}"

# Calico version (for CNI install URL)
export CALICO_VERSION="${CALICO_VERSION:-v3.28.0}"
