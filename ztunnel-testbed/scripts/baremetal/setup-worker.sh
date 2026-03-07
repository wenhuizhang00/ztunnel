#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Setup worker node (run from control-plane via SSH)
# =============================================================================
# Installs prerequisites on a remote worker node and joins it to the cluster.
#
# Usage (from control-plane):
#   ./scripts/baremetal/setup-worker.sh <worker-ip> [join-command]
#
# Two modes:
#   1. Install prereqs + join:  ./scripts/baremetal/setup-worker.sh 10.136.0.75 "kubeadm join ..."
#   2. Install prereqs only:    ./scripts/baremetal/setup-worker.sh 10.136.0.75 --prereqs-only
#
# Requirements:
#   - SSH key-based access to worker (ssh $WORKER_SSH_USER@<ip>)
#   - Worker has sudo without password
#   - This repo is available on the control-plane
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${PROJECT_ROOT}/config/baremetal.sh" 2>/dev/null || true
[ -f "${PROJECT_ROOT}/config/local.sh" ] && source "${PROJECT_ROOT}/config/local.sh" 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

WORKER_IP="${1:-}"
JOIN_CMD="${2:-}"
SSH_USER="${WORKER_SSH_USER:-${USER}}"

if [[ -z "$WORKER_IP" ]]; then
  echo "Usage: $0 <worker-ip> [join-command | --prereqs-only]"
  echo ""
  echo "Examples:"
  echo "  $0 10.136.0.75 --prereqs-only          # install prereqs on worker"
  echo "  $0 10.136.0.75 'kubeadm join ...'       # install prereqs + join"
  exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Test SSH connectivity
log_info "Testing SSH to ${SSH_USER}@${WORKER_IP}..."
if ! ssh $SSH_OPTS "${SSH_USER}@${WORKER_IP}" "echo ok" &>/dev/null; then
  log_error "Cannot SSH to ${SSH_USER}@${WORKER_IP}. Ensure SSH key is set up."
  exit 1
fi
log_ok "SSH to ${WORKER_IP} OK"

# Copy install-baremetal-prereqs.sh to worker and run it
log_info "Installing prerequisites on ${WORKER_IP}..."
scp $SSH_OPTS "${PROJECT_ROOT}/scripts/install-baremetal-prereqs.sh" "${SSH_USER}@${WORKER_IP}:/tmp/install-baremetal-prereqs.sh"

# Forward proxy env vars to the remote install
REMOTE_ENV=""
[[ -n "${HTTP_PROXY:-}" ]] && REMOTE_ENV+="export HTTP_PROXY='${HTTP_PROXY}'; "
[[ -n "${HTTPS_PROXY:-}" ]] && REMOTE_ENV+="export HTTPS_PROXY='${HTTPS_PROXY}'; "
[[ -n "${NO_PROXY:-}" ]] && REMOTE_ENV+="export NO_PROXY='${NO_PROXY}'; "

ssh $SSH_OPTS "${SSH_USER}@${WORKER_IP}" "${REMOTE_ENV} sudo bash /tmp/install-baremetal-prereqs.sh"
log_ok "Prerequisites installed on ${WORKER_IP}"

if [[ "$JOIN_CMD" == "--prereqs-only" ]] || [[ -z "$JOIN_CMD" ]]; then
  log_ok "Prereqs-only mode. To join later, run on ${WORKER_IP}:"
  echo "  sudo kubeadm join <control-plane>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
  exit 0
fi

# Join the worker to the cluster
log_info "Joining ${WORKER_IP} to cluster..."
ssh $SSH_OPTS "${SSH_USER}@${WORKER_IP}" "${REMOTE_ENV} sudo ${JOIN_CMD}"
log_ok "Worker ${WORKER_IP} joined the cluster"

# Wait for node to appear
log_info "Waiting for node to register (up to 30s)..."
for i in {1..30}; do
  if kubectl get nodes -o wide 2>/dev/null | grep -q "${WORKER_IP}"; then
    break
  fi
  sleep 1
done
kubectl get nodes -o wide | grep "${WORKER_IP}" && log_ok "Node ${WORKER_IP} registered" || log_info "Node may still be registering"
