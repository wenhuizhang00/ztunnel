# Bare Metal Kubernetes Deployment Guide

Create a standard Kubernetes cluster on bare metal using **kubeadm** (no k3s), managed with **kubectl**.

## Prerequisites

- At least 1 machine (control-plane), recommended 3 (1 control-plane + 2 workers)
- Ubuntu 22.04 / 24.04 or compatible Linux
- Installed: kubeadm, kubelet, kubectl, containerd (or docker)
- Network connectivity between nodes

### Install Kubernetes components (all nodes)

```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### Disable swap and load modules (all nodes)

```bash
sudo swapoff -a && sudo sed -i '/ swap / d' /etc/fstab
sudo modprobe overlay && sudo modprobe br_netfilter
```

## Create cluster

### 1. Run on control-plane node

Copy this repo to the control-plane node or clone via git, then:

```bash
cd ztunnel-testbed
./scripts/create-cluster-baremetal.sh
```

The script will:
- Run `kubeadm init`
- Configure kubeconfig
- Install Calico or Cilium CNI
- Print the worker join command

### 2. Run on worker nodes

Copy the `kubeadm join` command from the control-plane output and run on each worker:

```bash
# Replace <join-command> with the actual output
sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

Or use the script:

```bash
./scripts/baremetal/join-worker.sh kubeadm join ...
```

### 3. Copy kubeconfig to workstation

On control-plane:

```bash
scp ~/.kube/config user@your-laptop:~/.kube/ztunnel-baremetal-config
```

On workstation:

```bash
export KUBECONFIG=~/.kube/ztunnel-baremetal-config
# or
export KUBE_CONTEXT=kubernetes-admin@kubernetes  # if specifying context
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `CNI_PROVIDER` | CNI: calico or cilium | calico |
| `K8S_VERSION` | Kubernetes version | 1.30.0 |
| `POD_NETWORK_CIDR` | Pod network CIDR | 192.168.0.0/16 |
| `CALICO_VERSION` | Calico version | v3.28.0 |
| `CILIUM_VERSION` | Cilium version (when CNI_PROVIDER=cilium) | 1.16.0 |
| `CRI_SOCKET` | Container runtime socket | unix:///var/run/containerd/containerd.sock |
| `CONTROL_PLANE_ENDPOINT` | API endpoint for HA | empty (single-node) |

Cilium uses the Cilium CLI (no Helm). Installed with Istio ambient-compatible settings (cni.exclusive=false, socketLB.hostNamespaceOnly=true).

Override in `config/local.sh` or export before running scripts.

## Next steps

Once the cluster is ready, on your workstation:

```bash
make install    # Install Istio ambient
make deploy     # Deploy sample apps (grimlock, grimlock-baseline)
make test-func
```
