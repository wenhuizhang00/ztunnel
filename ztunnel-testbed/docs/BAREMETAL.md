# Bare Metal Kubernetes Deployment Guide

Create a standard Kubernetes cluster on bare metal using **kubeadm** (no k3s), managed with **kubectl**.

## Prerequisites

- At least 1 machine (control-plane), recommended 3 (1 control-plane + 2 workers)
- Ubuntu 22.04 / 24.04 or compatible Linux
- Network connectivity between nodes

### Dependencies (all nodes)

| Dependency | Purpose |
|------------|---------|
| kubeadm | Create cluster |
| kubelet | Node agent |
| kubectl | Cluster CLI |
| containerd | Container runtime |
| curl | Downloads |
| swap disabled | Kubernetes requirement |
| overlay, br_netfilter | Kernel modules |

### Install all prerequisites (recommended)

Run on **each** node (control-plane and workers):

```bash
cd ztunnel-testbed
sudo ./scripts/install-baremetal-prereqs.sh
```

This installs kubeadm, kubelet, kubectl, containerd; disables swap; loads modules; configures sysctl.

### Manual install (alternative)

If the script is not suitable, install manually:

```bash
# Ubuntu/Debian - Kubernetes
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Disable swap
sudo swapoff -a && sudo sed -i '/ swap / d' /etc/fstab

# Load modules
sudo modprobe overlay && sudo modprobe br_netfilter

# Containerd
sudo apt-get install -y containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable --now containerd
```

## Create cluster

### 1. Run on control-plane node

Copy this repo to the control-plane node or clone via git, then:

```bash
cd ztunnel-testbed
./scripts/create-cluster-baremetal.sh
```

If `kubeadm init` fails (e.g. "experimental API" error or partial run), reset and retry:

```bash
sudo kubeadm reset -f
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

### 3. Kubeconfig: control-plane vs workstation

**On control-plane** (where you ran `make create-baremetal`):
- Kubeconfig is at `~/.kube/config` (set by the script).
- Use the default; do **not** set `KUBECONFIG` to `ztunnel-baremetal-config` (that file does not exist on the control-plane).
- Verify: `kubectl get nodes`

**On workstation** (laptop, CI, etc.):
- First copy the kubeconfig from the control-plane:
  ```bash
  scp gsadmin@<control-plane-ip>:~/.kube/config ~/.kube/ztunnel-baremetal-config
  ```
- Then set KUBECONFIG:
  ```bash
  export KUBECONFIG=~/.kube/ztunnel-baremetal-config
  kubectl get nodes
  ```

**If kubectl shows "connection to localhost:8080 refused"**: `KUBECONFIG` likely points to a non-existent file. Run `unset KUBECONFIG` and use `~/.kube/config` (control-plane) or copy the file first (workstation).

## Proxy (corporate / behind firewall)

When behind an HTTP proxy, kubeadm may warn that connection to control-plane IP (e.g. 10.200.15.195) uses the proxy. Exclude private ranges and node IP:

```bash
export NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.200.15.195"
export no_proxy="${NO_PROXY}"
make create-baremetal
```

The script auto-adds node IP (from `hostname -I`) and pod/service CIDRs; extend in `config/local.sh` for multiple nodes.

### Containerd proxy (required for registry.k8s.io image pulls)

Containerd runs as a systemd service and does **not** inherit the shell's proxy. Set before `create-baremetal`:

```bash
export HTTP_PROXY="http://your-proxy:3128"
export HTTPS_PROXY="$HTTP_PROXY"
make create-baremetal
```

The script configures containerd's systemd drop-in and restarts it when `HTTP_PROXY` is set. If image pulls still timeout, ensure the proxy allows `registry.k8s.io` and that `NO_PROXY` excludes only internal IPs (not registry.k8s.io).

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
