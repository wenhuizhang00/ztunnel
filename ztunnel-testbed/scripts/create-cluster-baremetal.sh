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
log_step() { echo -e "${BLUE}[$(date '+%H:%M:%S')] [$1]${NC} $2"; }
log_step_ok() {
  local elapsed="${3:-}"
  [[ -n "$elapsed" ]] && echo -e "${GREEN}[$(date '+%H:%M:%S')] [$1] OK${NC} $2 (${elapsed})" || echo -e "${GREEN}[$(date '+%H:%M:%S')] [$1] OK${NC} $2"
}

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

# Generate kubeadm config (remove stale cache)
KUBEADM_CONFIG="${PROJECT_ROOT}/.cache/kubeadm-config.yaml"
mkdir -p "${PROJECT_ROOT}/.cache"
rm -f "$KUBEADM_CONFIG"
export K8S_VERSION POD_NETWORK_CIDR CRI_SOCKET
export CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-}"
if [[ -f "${PROJECT_ROOT}/config/kubeadm-config.yaml.template" ]]; then
  # v1beta3: stable for K8s 1.30. v1beta4 requires K8s 1.31+ and --allow-experimental-api
  export KUBEADM_API_VERSION="v1beta3"
  export K8S_VERSION POD_NETWORK_CIDR CRI_SOCKET KUBEADM_API_VERSION
  envsubst '$K8S_VERSION,$POD_NETWORK_CIDR,$CRI_SOCKET,$KUBEADM_API_VERSION' \
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

# Bypass proxy for cluster-internal traffic (kubeadm, control-plane IP, pod/service CIDRs)
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"
export NO_PROXY="${NO_PROXY},10.96.0.0/12,${POD_NETWORK_CIDR},10.0.0.0/8,172.16.0.0/12"
# Add node IP if detectable (10.200.x.x etc)
NODE_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
[[ -n "$NODE_IP" ]] && export NO_PROXY="${NO_PROXY},${NODE_IP}"
# Some tools use lowercase
export no_proxy="${NO_PROXY}"
log_info "NO_PROXY includes cluster CIDRs and node IP for proxy bypass"

# Containerd needs proxy for registry.k8s.io - configure if HTTP_PROXY set
CONTAINERD_PROXY="${CONTAINERD_HTTP_PROXY:-${HTTP_PROXY:-${https_proxy:-}}}"
[[ -z "$CONTAINERD_PROXY" ]] && CONTAINERD_PROXY="${HTTPS_PROXY:-${http_proxy:-}}"
if [[ -n "$CONTAINERD_PROXY" ]]; then
  PROXY_CONF="/etc/systemd/system/containerd.service.d/http-proxy.conf"
  if [[ ! -f "$PROXY_CONF" ]] || ! grep -q "HTTP_PROXY" "$PROXY_CONF" 2>/dev/null; then
    log_info "Configuring containerd proxy for registry.k8s.io pulls..."
    sudo mkdir -p "$(dirname "$PROXY_CONF")"
    sudo tee "$PROXY_CONF" >/dev/null <<EOF
[Service]
Environment="HTTP_PROXY=${CONTAINERD_PROXY}"
Environment="HTTPS_PROXY=${CONTAINERD_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart containerd
    sleep 3
    log_ok "Containerd restarted with proxy"
  fi
else
  log_warn "No HTTP_PROXY/HTTPS_PROXY. If behind corporate proxy, image pulls may time out. Set: export HTTP_PROXY=http://proxy:3128"
fi

# If cluster already exists (from previous run or partial failure), reset first
if [[ -f /etc/kubernetes/admin.conf ]] || [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] || ss -tlnp 2>/dev/null | grep -q ':6443 '; then
  log_info "Existing cluster detected. Running kubeadm reset -f..."
  sudo kubeadm reset -f 2>/dev/null || true
  sudo rm -rf /etc/cni/net.d 2>/dev/null || true
  log_ok "Reset complete. Proceeding with fresh init."
fi

# CHOKE: kubeadm init (preflight, image pull from registry.k8s.io, etcd, control-plane)
log_step "KUBEADM" "Running kubeadm init (preflight + image pull + etcd + control-plane - may take 2-5 min)..."
kubeadm_start=$(date +%s)
sudo -E kubeadm init --config "$KUBEADM_CONFIG"
log_step_ok "KUBEADM" "kubeadm init complete" "$(( $(date +%s) - kubeadm_start ))s"

# Setup kubeconfig for current user
log_step "KUBECONFIG" "Setting up kubeconfig..."
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"
log_ok "kubeconfig ready"
# Verify kubectl works (in new shells, use: export KUBECONFIG=$HOME/.kube/config or unset KUBECONFIG if it pointed to a missing file)
if ! kubectl get nodes &>/dev/null; then
  log_warn "kubectl get nodes failed. Ensure KUBECONFIG is set: export KUBECONFIG=$HOME/.kube/config"
fi

# Install CNI
if [[ "${CNI_PROVIDER:-calico}" == "cilium" ]]; then
  log_step "CILIUM" "Installing Cilium CNI (Istio ambient compatible, no Helm)..."
  source "${PROJECT_ROOT}/config/cilium.sh" 2>/dev/null || true
  CILIUM_CLI=$(command -v cilium 2>/dev/null || echo "${PROJECT_ROOT}/bin/cilium")
  if [[ ! -x "$CILIUM_CLI" ]]; then
    log_step "CILIUM" "Downloading Cilium CLI (network - may be slow behind proxy)..."
    CILIUM_CLI_VERSION=$(curl -sL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt 2>/dev/null || echo "v0.18.7")
    CLI_ARCH=amd64; [[ "$(uname -m)" == "aarch64" ]] || [[ "$(uname -m)" == "arm64" ]] && CLI_ARCH=arm64
    mkdir -p "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/.cache"
    cilium_start=$(date +%s)
    curl -sL --fail -o "${PROJECT_ROOT}/.cache/cilium-cli.tar.gz" "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz" || { log_error "Failed to download Cilium CLI"; exit 1; }
    tar xzf "${PROJECT_ROOT}/.cache/cilium-cli.tar.gz" -C "${PROJECT_ROOT}/bin"
    chmod +x "${PROJECT_ROOT}/bin/cilium"
    CILIUM_CLI="${PROJECT_ROOT}/bin/cilium"
    log_step_ok "CILIUM" "Cilium CLI downloaded" "$(( $(date +%s) - cilium_start ))s"
  fi
  log_step "CILIUM" "Running cilium install (pulling images + --wait)..."
  cilium_install_start=$(date +%s)
  "$CILIUM_CLI" install --version "v${CILIUM_VERSION:-1.16.0}" \
    --set cni.exclusive=false \
    --set socketLB.hostNamespaceOnly=true \
    --set kubeProxyReplacement=false \
    --wait
  log_step "CILIUM" "Waiting for cilium DaemonSet rollout (timeout 300s)..."
  kubectl rollout status daemonset/cilium -n kube-system --timeout=300s
  log_step_ok "CILIUM" "Cilium ready" "$(( $(date +%s) - cilium_install_start ))s"
else
  log_step "CALICO" "Installing Calico CNI (${CALICO_VERSION}) - fetching manifests..."
  calico_start=$(date +%s)
  # Use --server-side to avoid "metadata.annotations: Too long" (CRD annotation 256KB limit)
  kubectl apply --server-side -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/operator-crds.yaml"
  kubectl apply --server-side -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
  kubectl apply -f "${PROJECT_ROOT}/manifests/cni/calico-custom-resources.yaml"
  log_step "CALICO" "Waiting for Calico pods (sleep 15s + wait up to 180s)..."
  sleep 15
  kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=180s 2>/dev/null || \
    kubectl wait --for=condition=available deployment -n tigera-operator tigera-operator --timeout=180s 2>/dev/null || true
  log_step_ok "CALICO" "Calico ready" "$(( $(date +%s) - calico_start ))s"
fi

log_ok "Control-plane ready."

# Untaint control-plane for single-node or scheduling
log_info "Allowing pods on control-plane (single-node testbed)..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

# Output join command for workers (non-fatal - cluster is ready either way)
echo ""
log_ok "Cluster created."
# Try with user kubeconfig first (avoids sudo env/proxy issues), then sudo
if KUBECONFIG="$HOME/.kube/config" kubeadm token create --print-join-command 2>/dev/null; then
  echo ""
elif sudo -E env KUBECONFIG=/etc/kubernetes/admin.conf kubeadm token create --print-join-command 2>/dev/null; then
  echo ""
else
  log_warn "Could not create join token (Forbidden). For single-node, ignore. For workers, run manually:"
  echo "  kubeadm token create --print-join-command"
  echo ""
fi
echo ""
log_info "On control-plane: kubectl uses ~/.kube/config (already set)."
log_info "From workstation: scp $USER@<control-plane>:~/.kube/config ~/.kube/config"
log_info "If kubectl fails, run: unset KUBECONFIG  (if it pointed to a non-existent file)"
