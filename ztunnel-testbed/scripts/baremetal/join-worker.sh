#!/usr/bin/env bash
# =============================================================================
# Join worker node to bare metal Kubernetes cluster
# =============================================================================
# Run on each worker node. Get join command from control-plane:
#   kubeadm token create --print-join-command
# Or copy join command from create-cluster-baremetal.sh output.
# =============================================================================

set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 kubeadm join <control-plane>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
  echo "Get the join command from control-plane: kubeadm token create --print-join-command"
  exit 1
fi

echo "[INFO] Joining worker to cluster..."
sudo "$@"
echo "[OK] Worker joined."
