#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Bare Metal Kubernetes Configuration
# =============================================================================
# For kubeadm-based cluster on bare metal. Not k3s.
# Supports two modes:
#   single-node: control-plane runs workloads (default)
#   multi-node:  control-plane + separate worker node(s)
# =============================================================================

# --- Cluster topology ---
# WORKER_NODES: comma-separated IPs of worker nodes to join automatically.
# Leave empty for single-node mode (control-plane also runs workloads).
# Example: WORKER_NODES="10.136.0.75" or WORKER_NODES="10.136.0.75,10.136.0.76"
export WORKER_NODES="${WORKER_NODES:-}"

# Node IPs (used for node affinity labels and cross-node tests)
# Control-plane: runs server pods (sapi ssh --host 10.136.0.75)
# Worker: runs client pods (sapi ssh --host 10.136.11.5)
export CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-10.136.0.75}"
export WORKER_IP="${WORKER_IP:-10.136.11.5}"

# SSH user for remote worker operations (must have passwordless sudo on workers)
export WORKER_SSH_USER="${WORKER_SSH_USER:-${USER}}"

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

# Cilium version (when CNI_PROVIDER=cilium, see also config/cilium.sh)
export CILIUM_VERSION="${CILIUM_VERSION:-1.16.0}"

# CRI socket (containerd default)
export CRI_SOCKET="${CRI_SOCKET:-unix:///var/run/containerd/containerd.sock}"

# --- Derived helpers (used by scripts) ---
# Returns "multi" if WORKER_NODES is set, "single" otherwise
get_node_mode() {
  if [[ -n "${WORKER_NODES:-}" ]]; then
    echo "multi"
  else
    echo "single"
  fi
}

# Returns array of worker IPs from WORKER_NODES
get_worker_ips() {
  echo "${WORKER_NODES:-}" | tr ',' '\n' | sed '/^$/d'
}
