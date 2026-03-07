#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Install bare metal prerequisites for kubeadm cluster
# =============================================================================
# Installs on Ubuntu/Debian: kubeadm, kubelet, kubectl, containerd
# Disables swap, loads overlay and br_netfilter modules.
# Run with sudo or as root on each node (control-plane and workers).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PROJECT_ROOT}/config/versions.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/config/baremetal.sh" 2>/dev/null || true
[ -f "${PROJECT_ROOT}/config/local.sh" ] && source "${PROJECT_ROOT}/config/local.sh" 2>/dev/null || true

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

# Detect Linux
[[ "$(uname -s)" == "Linux" ]] || { log_error "This script is for Linux only."; exit 1; }

# Detect Ubuntu/Debian
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) log_error "Unsupported OS: ${ID:-unknown}. See docs/BAREMETAL.md for manual install."; exit 1 ;;
  esac
else
  log_error "Cannot detect OS. See docs/BAREMETAL.md for manual install."
  exit 1
fi

log_info "Installing bare metal prerequisites (Ubuntu/Debian)..."

# 1. Load kernel modules
log_info "Loading overlay and br_netfilter modules..."
sudo modprobe overlay 2>/dev/null || true
sudo modprobe br_netfilter 2>/dev/null || true
log_ok "Modules loaded"

# 2. Sysctl (optional but recommended)
log_info "Setting sysctl for Kubernetes..."
sudo tee /etc/sysctl.d/99-kubernetes.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system >/dev/null 2>&1 || true
log_ok "Sysctl configured"

# 3. Disable swap
log_info "Disabling swap..."
sudo swapoff -a 2>/dev/null || true
if grep -q '\sswap\s' /etc/fstab 2>/dev/null; then
  sudo sed -i '/ swap / d' /etc/fstab
  log_ok "Swap removed from fstab"
fi
log_ok "Swap disabled"

# 4. CHOKE: apt update + install (network)
log_step "APT" "Installing apt packages (update + install, may be slow)..."
apt_start=$(date +%s)
sudo apt-get update -qq
sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg
log_step_ok "APT" "apt packages installed" "$(( $(date +%s) - apt_start ))s"

# 5. CHOKE: Add Kubernetes repo (network fetch of Release.key)
K8S_APT_KEY="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
K8S_LIST="/etc/apt/sources.list.d/kubernetes.list"
K8S_VERSION="${K8S_VERSION:-1.30.0}"
K8S_MAJOR_MINOR="${K8S_VERSION%.*}"  # 1.30.0 -> 1.30

log_step "K8S-REPO" "Adding Kubernetes apt repository (v${K8S_MAJOR_MINOR}) - network fetch..."
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/Release.key" | sudo gpg --dearmor -o "${K8S_APT_KEY}"
echo "deb [signed-by=${K8S_APT_KEY}] https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/ /" | sudo tee "${K8S_LIST}"

# 6. CHOKE: Install kubelet, kubeadm, kubectl (network)
log_step "K8S" "Installing kubelet, kubeadm, kubectl (apt, may take 1-2 min)..."
k8s_start=$(date +%s)
sudo apt-get update -qq
sudo apt-get install -y -qq kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
log_step_ok "K8S" "kubelet, kubeadm, kubectl installed" "$(( $(date +%s) - k8s_start ))s"

# 7. CHOKE: Install containerd (apt)
log_step "CONTAINERD" "Installing containerd (apt + systemctl)..."
sudo apt-get install -y -qq containerd
sudo mkdir -p /etc/containerd
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml 2>/dev/null; then
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
fi
sudo systemctl enable --now containerd
sudo systemctl restart containerd 2>/dev/null || true
log_step_ok "CONTAINERD" "containerd running"

echo ""
log_ok "Prerequisites installed. Next: make create-baremetal"
echo ""
