#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Install prerequisites and join worker node to cluster
# =============================================================================
# Run this script directly ON the worker node (not via SSH).
# It installs all k8s prerequisites and joins the cluster.
#
# Usage:
#   # Get join command from control-plane:
#   #   kubeadm token create --print-join-command
#   # Then run on the worker:
#
#   sudo ./scripts/baremetal/install-and-join-worker.sh \
#     --join "kubeadm join 10.136.11.5:6443 --token xxx --discovery-token-ca-cert-hash sha256:yyy"
#
#   # Or install prereqs only (join later manually):
#   sudo ./scripts/baremetal/install-and-join-worker.sh --prereqs-only
#
#   # Or reset an existing node and rejoin:
#   sudo ./scripts/baremetal/install-and-join-worker.sh --reset \
#     --join "kubeadm join 10.136.11.5:6443 --token xxx --discovery-token-ca-cert-hash sha256:yyy"
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step() { echo -e "${BLUE}[$(date '+%H:%M:%S')] [$1]${NC} $2"; }
log_step_ok() {
  local elapsed="${3:-}"
  [[ -n "$elapsed" ]] && echo -e "${GREEN}[$(date '+%H:%M:%S')] [$1] OK${NC} $2 (${elapsed})" || echo -e "${GREEN}[$(date '+%H:%M:%S')] [$1] OK${NC} $2"
}

# Parse arguments
JOIN_CMD=""
PREREQS_ONLY=0
DO_RESET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --join)
      JOIN_CMD="$2"
      shift 2
      ;;
    --prereqs-only)
      PREREQS_ONLY=1
      shift
      ;;
    --reset)
      DO_RESET=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --join \"kubeadm join ...\"   Install prereqs + join cluster"
      echo "  --prereqs-only              Install prereqs only (join later)"
      echo "  --reset                     Reset existing node before joining"
      echo ""
      echo "Examples:"
      echo "  # Get join command from control-plane first:"
      echo "  #   kubeadm token create --print-join-command"
      echo ""
      echo "  # Install and join:"
      echo "  sudo $0 --join 'kubeadm join 10.136.11.5:6443 --token xxx --discovery-token-ca-cert-hash sha256:yyy'"
      echo ""
      echo "  # Reset old node and rejoin:"
      echo "  sudo $0 --reset --join 'kubeadm join 10.136.11.5:6443 --token xxx ...'"
      echo ""
      echo "  # Install prereqs only:"
      echo "  sudo $0 --prereqs-only"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      echo "Run $0 --help for usage"
      exit 1
      ;;
  esac
done

if [[ "$PREREQS_ONLY" -eq 0 ]] && [[ -z "$JOIN_CMD" ]]; then
  log_error "Must specify --join or --prereqs-only"
  echo ""
  echo "Get the join command from the control-plane:"
  echo "  kubeadm token create --print-join-command"
  echo ""
  echo "Then run:"
  echo "  sudo $0 --join 'kubeadm join 10.136.11.5:6443 --token xxx ...'"
  echo ""
  echo "Or install prereqs only:"
  echo "  sudo $0 --prereqs-only"
  exit 1
fi

NODE_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
log_info "Setting up worker node: $(hostname) ($NODE_IP)"

# ── Step 1: Reset existing node if requested ──
if [[ "$DO_RESET" -eq 1 ]]; then
  log_step "RESET" "Resetting existing kubeadm state..."
  kubeadm reset -f 2>/dev/null || true
  rm -rf /etc/cni/net.d/* 2>/dev/null || true
  systemctl restart containerd 2>/dev/null || true
  sleep 3
  log_step_ok "RESET" "Node reset complete"
fi

# ── Step 2: Install prerequisites ──
log_step "PREREQS" "Installing prerequisites..."
prereq_start=$(date +%s)

if [[ -f "${PROJECT_ROOT}/scripts/install-baremetal-prereqs.sh" ]]; then
  bash "${PROJECT_ROOT}/scripts/install-baremetal-prereqs.sh"
else
  log_info "install-baremetal-prereqs.sh not found, installing inline..."

  # Kernel modules
  modprobe overlay 2>/dev/null || true
  modprobe br_netfilter 2>/dev/null || true

  # Sysctl
  tee /etc/sysctl.d/99-kubernetes.conf >/dev/null <<'SYSEOF'
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYSEOF
  sysctl --system >/dev/null 2>&1 || true

  # Disable swap
  swapoff -a 2>/dev/null || true
  sed -i '/ swap / d' /etc/fstab 2>/dev/null || true

  # Install k8s packages
  apt-get update -qq
  apt-get install -y -qq apt-transport-https ca-certificates curl gpg
  mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
  apt-get update -qq
  apt-get install -y -qq kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl

  # Install containerd
  apt-get install -y -qq containerd
  mkdir -p /etc/containerd
  containerd config default | tee /etc/containerd/config.toml >/dev/null
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sed -i 's|registry.k8s.io/pause:3\.[678]|registry.k8s.io/pause:3.9|g' /etc/containerd/config.toml 2>/dev/null || true
  systemctl enable --now containerd
  systemctl restart containerd
fi

log_step_ok "PREREQS" "Prerequisites installed" "$(( $(date +%s) - prereq_start ))s"

# ── Step 3: Ensure CNI directory exists ──
mkdir -p /etc/cni/net.d

# ── Step 4: Join cluster ──
if [[ "$PREREQS_ONLY" -eq 1 ]]; then
  echo ""
  log_ok "Prerequisites installed. Node is ready to join a cluster."
  echo ""
  echo "  To join, get the command from the control-plane:"
  echo "    kubeadm token create --print-join-command"
  echo ""
  echo "  Then run on this node:"
  echo "    sudo kubeadm join <control-plane>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
  echo ""
  exit 0
fi

# Reset if node was previously joined (stale kubelet.conf, pki)
if [[ -f /etc/kubernetes/kubelet.conf ]] || [[ -f /etc/kubernetes/pki/ca.crt ]]; then
  log_warn "Node has stale kubeadm state. Resetting first..."
  kubeadm reset -f 2>/dev/null || true
  rm -rf /etc/cni/net.d/* 2>/dev/null || true
  mkdir -p /etc/cni/net.d
  systemctl restart containerd 2>/dev/null || true
  sleep 3
fi

log_step "JOIN" "Joining cluster..."
join_start=$(date +%s)
eval "$JOIN_CMD"
log_step_ok "JOIN" "Joined cluster" "$(( $(date +%s) - join_start ))s"

echo ""
log_ok "Worker node $(hostname) ($NODE_IP) joined the cluster."
echo ""
echo "  On the control-plane, verify:"
echo "    kubectl get nodes -o wide"
echo ""
