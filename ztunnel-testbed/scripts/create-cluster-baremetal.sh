#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Create Kubernetes cluster on bare metal (kubeadm)
# =============================================================================
# Run on control-plane node. Uses kubeadm + Calico. Not k3s.
# Prereqs on all nodes: kubeadm, kubelet, kubectl, containerd (or docker)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load config
source "${PROJECT_ROOT}/config/versions.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/config/baremetal.sh" 2>/dev/null || true
[ -f "${PROJECT_ROOT}/config/local.sh" ] && source "${PROJECT_ROOT}/config/local.sh" 2>/dev/null || true

# CRI socket (containerd default)
export CRI_SOCKET="${CRI_SOCKET:-unix:///var/run/containerd/containerd.sock}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

log_info "Creating Kubernetes cluster on bare metal (kubeadm, no k3s)"

# --- Dependency checks ---
missing=()

# Commands
for cmd in kubeadm kubectl kubelet curl; do
  command -v "$cmd" &>/dev/null || missing+=("$cmd")
done

# Container runtime (containerd or docker)
case "${CRI_SOCKET}" in
  *containerd*)
    if ! command -v containerd &>/dev/null; then
      missing+=("containerd")
    else
      sock="${CRI_SOCKET#unix://}"
      [[ -S "$sock" ]] || systemctl is-active containerd &>/dev/null || missing+=("containerd (run: sudo systemctl start containerd)")
    fi
    ;;
  *docker*)
    command -v docker &>/dev/null || missing+=("docker")
    ;;
  *)
    command -v containerd &>/dev/null || command -v docker &>/dev/null || missing+=("containerd or docker")
    ;;
esac

# Swap must be off (Kubernetes requirement)
if [[ -f /proc/swaps ]]; then
  swap_kb=$(awk 'NR>1 {sum+=$3} END {print sum+0}' /proc/swaps)
  [[ "${swap_kb:-0}" -gt 0 ]] && missing+=("swap (run: sudo swapoff -a)")
fi

# Kernel modules (warn only, kubeadm may work anyway)
for mod in overlay br_netfilter; do
  lsmod 2>/dev/null | grep -q "^${mod}\s" || log_warn "Module $mod not loaded (recommended: sudo modprobe $mod)"
done

if [[ ${#missing[@]} -gt 0 ]]; then
  log_error "Missing prerequisites: ${missing[*]}"
  echo ""
  echo "  Install all at once (Ubuntu/Debian):"
  echo "    sudo ./scripts/install-baremetal-prereqs.sh"
  echo ""
  echo "  Or: make install-prereqs-baremetal"
  echo ""
  echo "  See docs/BAREMETAL.md and README.md for details."
  exit 1
fi

log_ok "All prerequisites satisfied"

# Generate kubeadm config
KUBEADM_CONFIG="${PROJECT_ROOT}/.cache/kubeadm-config.yaml"
mkdir -p "${PROJECT_ROOT}/.cache"
export K8S_VERSION POD_NETWORK_CIDR CRI_SOCKET
export CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-}"
if [[ -f "${PROJECT_ROOT}/config/kubeadm-config.yaml.template" ]]; then
  export K8S_VERSION POD_NETWORK_CIDR CRI_SOCKET
  envsubst '$K8S_VERSION,$POD_NETWORK_CIDR,$CRI_SOCKET' \
    < "${PROJECT_ROOT}/config/kubeadm-config.yaml.template" \
    > "$KUBEADM_CONFIG"
  # Set controlPlaneEndpoint for HA; edit template for custom value
  if [[ -n "${CONTROL_PLANE_ENDPOINT:-}" ]]; then
    if sed --version 2>/dev/null | grep -q GNU; then
      sed -i "s|# controlPlaneEndpoint.*|controlPlaneEndpoint: \"${CONTROL_PLANE_ENDPOINT}\"|" "$KUBEADM_CONFIG"
    else
      sed -i '' "s|# controlPlaneEndpoint.*|controlPlaneEndpoint: \"${CONTROL_PLANE_ENDPOINT}\"|" "$KUBEADM_CONFIG"
    fi
  fi
else
  cp "${PROJECT_ROOT}/config/kubeadm-config.yaml" "$KUBEADM_CONFIG"
fi

log_info "Running kubeadm init..."
sudo kubeadm init --config "$KUBEADM_CONFIG"

# Setup kubeconfig for current user
log_info "Setting up kubeconfig..."
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

# Install CNI
if [[ "${CNI_PROVIDER:-calico}" == "cilium" ]]; then
  log_info "Installing Cilium CNI (Istio ambient compatible, no Helm)..."
  source "${PROJECT_ROOT}/config/cilium.sh" 2>/dev/null || true
  CILIUM_CLI=$(command -v cilium 2>/dev/null || echo "${PROJECT_ROOT}/bin/cilium")
  if [[ ! -x "$CILIUM_CLI" ]]; then
    log_info "Downloading Cilium CLI..."
    CILIUM_CLI_VERSION=$(curl -sL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt 2>/dev/null || echo "v0.18.7")
    CLI_ARCH=amd64; [[ "$(uname -m)" == "aarch64" ]] || [[ "$(uname -m)" == "arm64" ]] && CLI_ARCH=arm64
    mkdir -p "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/.cache"
    curl -sL --fail -o "${PROJECT_ROOT}/.cache/cilium-cli.tar.gz" "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz" || { log_error "Failed to download Cilium CLI"; exit 1; }
    tar xzf "${PROJECT_ROOT}/.cache/cilium-cli.tar.gz" -C "${PROJECT_ROOT}/bin"
    chmod +x "${PROJECT_ROOT}/bin/cilium"
    CILIUM_CLI="${PROJECT_ROOT}/bin/cilium"
  fi
  "$CILIUM_CLI" install --version "v${CILIUM_VERSION:-1.16.0}" \
    --set cni.exclusive=false \
    --set socketLB.hostNamespaceOnly=true \
    --set kubeProxyReplacement=false \
    --wait
  kubectl rollout status daemonset/cilium -n kube-system --timeout=300s
else
  log_info "Installing Calico CNI (${CALICO_VERSION})..."
  kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/operator-crds.yaml" 2>/dev/null || true
  kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
  kubectl create -f "${PROJECT_ROOT}/manifests/cni/calico-custom-resources.yaml"
  log_info "Waiting for CNI to be ready..."
  sleep 15
  kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=180s 2>/dev/null || \
    kubectl wait --for=condition=available deployment -n tigera-operator tigera-operator --timeout=180s 2>/dev/null || true
fi

log_ok "Control-plane ready."

# Untaint control-plane for single-node or scheduling
log_info "Allowing pods on control-plane (single-node testbed)..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

# Output join command for workers
echo ""
log_ok "Cluster created. To add worker nodes, run on each worker:"
echo ""
sudo kubeadm token create --print-join-command
echo ""
log_info "Copy kubeconfig to your workstation: scp $USER@<control-plane>:/home/$USER/.kube/config ~/.kube/ztunnel-baremetal-config"
