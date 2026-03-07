# ztunnel-testbed

A production-oriented testbed for **Istio ambient mode** and **ztunnel** on Kubernetes. Supports bare metal (kubeadm), functionality tests, and performance benchmarks.

## Features

- **Kubernetes**: Existing cluster or bare metal (kubeadm, no k3s)
- **CNI**: Calico (default) or Cilium (no Helm, Cilium CLI)
- **Istio ambient**: Installed via `istioctl`
- **Gateway API CRDs**: For traffic routing
- **Sample apps**: http-echo + curl-client in `grimlock` (ambient) and `grimlock-baseline` (non-ambient)
- **Functionality tests**: Cluster, Istio, ztunnel, Pod-to-Pod, Service, workload visibility
- **Performance tests**: fortio/curl, ambient vs baseline
- **Inspection**: ztunnel workloads, logs, config

## Dependencies

### All setups

| Dependency | Purpose |
|------------|---------|
| kubectl | Cluster access |
| curl | Downloads (Istio, manifests) |

### Bare metal only (for `make create-baremetal`)

| Dependency | Purpose |
|------------|---------|
| kubeadm | Create cluster |
| kubelet | Node agent |
| kubectl | Cluster CLI |
| containerd (or docker) | Container runtime |
| swap disabled | Kubernetes requirement |
| overlay, br_netfilter | Kernel modules |

**Install all bare metal deps (Ubuntu/Debian):**

```bash
# Run on each node (control-plane and workers) with sudo
sudo ./scripts/install-baremetal-prereqs.sh
```

Or: `make install-prereqs-baremetal` (prints the command).

## Quick Start

### Option A: Existing cluster

```bash
# Ensure kubectl points to your cluster
kubectl cluster-info

# Full setup: verify cluster, install Istio, deploy sample apps
make setup

# Run tests
make test-func
make test-perf
```

### Option B: Bare metal (create cluster first)

```bash
# 0. On all nodes: install prerequisites (one-time)
sudo ./scripts/install-baremetal-prereqs.sh

# 1. On control-plane node: create cluster
make create-baremetal

# 2. On each worker: run the kubeadm join command printed above

# 3. Copy kubeconfig to workstation, then:
export KUBECONFIG=~/.kube/ztunnel-baremetal-config
make setup
make test-func
```

### Option C: Other cluster tools (minikube, kind, etc.)

```bash
# Create cluster with your preferred tool, then:
make setup
make test-func
```

## Workflow

| Step | Command | Description |
|------|---------|-------------|
| 1 | `make create` | Verify kubectl can reach cluster (or `make create-baremetal` on bare metal) |
| 2 | `make install` | Install Istio ambient mode |
| 3 | `make deploy` | Deploy sample apps |
| 4 | `make test-func` | Run functionality tests |
| 5 | `make test-perf` | Run performance tests |

**Note**: `make create` only verifies connectivity. It does not create a cluster. Use `make create-baremetal` to create a cluster on bare metal.

## Make Targets

| Target | Description |
|--------|-------------|
| `make setup` | Verify cluster + install Istio + deploy apps |
| `make create` | Verify kubectl cluster connectivity |
| `make create-baremetal` | Create cluster on bare metal (kubeadm) |
| `make install-prereqs-baremetal` | Print install command for bare metal deps |
| `make install` | Install Istio ambient only |
| `make install-cilium` | Install Cilium CNI (no Helm, Istio compatible) |
| `make deploy` | Deploy sample apps only |
| `make build-images` | Build local http-echo, curl-client, fortio images |
| `make load-images` | Load local images into kind/minikube |
| `make test-func` | Run functionality tests |
| `make test-perf` | Run performance tests |
| `make bench-ambient` | Performance test (ambient only) |
| `make bench-baseline` | Performance test (baseline only) |
| `make inspect` | Inspect ztunnel state |
| `make clean` | Uninstall Istio, remove sample apps |

## Local Images

Use locally-built images (for air-gapped environments or to avoid pulling from registries):

```bash
# 1. Build images
make build-images

# 2. Load into cluster (kind/minikube; bare metal uses local images if built on same node)
make load-images

# 3. Deploy with local images
USE_LOCAL_IMAGES=1 make deploy
```

Or set in `config/local.sh`:
```bash
USE_LOCAL_IMAGES=1
IMAGE_REGISTRY="localhost/ztunnel-testbed"
```

Images: `images/http-echo`, `images/curl-client`, `images/fortio` (Dockerfiles included).

## Cilium CNI

Install Cilium on an existing cluster (Istio ambient compatible, no Helm):

```bash
make install-cilium
```

For bare metal with Cilium instead of Calico:

```bash
CNI_PROVIDER=cilium make create-baremetal
```

Remove existing CNI before installing Cilium.

## Directory Structure

```
ztunnel-testbed/
├── images/
│   ├── http-echo/       # Local http-echo (hashicorp/http-echo compatible)
│   │   ├── Dockerfile
│   │   └── main.go
│   ├── curl-client/     # Local curl (curlimages/curl compatible)
│   │   └── Dockerfile
│   └── fortio/          # Local fortio (fortio/fortio compatible)
│       └── Dockerfile
├── config/
│   ├── versions.sh          # Istio, Gateway API versions
│   ├── cluster.sh           # KUBE_CONTEXT (optional)
│   ├── baremetal.sh         # Bare metal: CNI, K8S_VERSION, POD_NETWORK_CIDR
│   ├── cilium.sh            # Cilium version
│   ├── kubeadm-config.yaml  # kubeadm init config
│   ├── kubeadm-config.yaml.template
│   ├── local.sh.example     # Template for overrides
│   └── local.sh             # (gitignored) Your overrides
├── manifests/
│   ├── namespace-ambient.yaml      # grimlock namespace with ambient label
│   ├── sample-apps/                # -> grimlock namespace
│   │   └── simple-http-server.yaml.template
│   ├── sample-apps-baseline/       # -> grimlock-baseline namespace
│   │   └── http-echo-baseline.yaml.template
│   ├── performance/
│   │   └── fortio-client.yaml
│   └── cni/
│       └── calico-custom-resources.yaml
├── scripts/
│   ├── common.sh
│   ├── create-cluster.sh
│   ├── create-cluster-baremetal.sh
│   ├── install-baremetal-prereqs.sh
│   ├── install-istio.sh
│   ├── install-cilium.sh
│   ├── deploy-sample-apps.sh
│   ├── run-functionality-tests.sh
│   ├── run-performance-tests.sh
│   ├── ztunnel-inspect.sh
│   ├── setup-all.sh
│   └── cleanup.sh
├── scripts/baremetal/
│   └── join-worker.sh
├── tests/
│   ├── lib.sh
│   ├── functionality/
│   │   ├── test-cluster-ready.sh
│   │   ├── test-gateway-api.sh
│   │   ├── test-istiod-ready.sh
│   │   ├── test-ztunnel-ready.sh
│   │   ├── test-namespace-ambient.sh
│   │   ├── test-sample-app-running.sh
│   │   ├── test-pod-to-pod.sh
│   │   ├── test-pod-to-service.sh
│   │   ├── test-ztunnel-workloads.sh
│   │   └── test-mtls-policy.sh
│   └── performance/
│       └── run-bench.sh
├── docs/
│   ├── BAREMETAL.md
│   └── STRUCTURE.md
├── Makefile
└── README.md
```

## Configuration

Copy `config/local.sh.example` to `config/local.sh` and customize:

```bash
# Versions
ISTIO_VERSION="1.29.0"
GATEWAY_API_VERSION="v1.4.0"

# Cluster
KUBE_CONTEXT="my-context"   # Optional

# Istio platform (GKE, EKS, k3d, minikube)
ISTIO_PLATFORM="gke"

# Bare metal CNI
CNI_PROVIDER="cilium"       # calico (default) | cilium
CILIUM_VERSION="1.16.0"
```

## Functionality Tests

| Test | Description |
|------|-------------|
| test-cluster-ready | All nodes Ready |
| test-gateway-api | Gateway API CRDs installed |
| test-istiod-ready | Istiod deployment ready |
| test-ztunnel-ready | ztunnel DaemonSet ready |
| test-namespace-ambient | grimlock has ambient label |
| test-sample-app-running | http-echo and curl-client running |
| test-pod-to-pod | Pod → Pod IP (via ztunnel) |
| test-pod-to-service | Pod → Service → Pod |
| test-ztunnel-workloads | `istioctl ztunnel-config workloads` |
| test-mtls-policy | mTLS/policy placeholder |

## Performance Tests

- **Modes**: `MODE=ambient`, `MODE=baseline`, or `MODE=both` (default)
- **Params**: `CONCURRENCY`, `REQUESTS`, `DURATION`
- **Output**: `.bench-results/<mode>-<timestamp>.txt`

```bash
CONCURRENCY=8 REQUESTS=10000 ./scripts/run-performance-tests.sh
```

Demo benchmark only; not for production capacity planning.

## Inspecting ztunnel

```bash
./scripts/ztunnel-inspect.sh all
./scripts/ztunnel-inspect.sh workloads
./scripts/ztunnel-inspect.sh pods
./scripts/ztunnel-inspect.sh logs 100
./scripts/ztunnel-inspect.sh certificates
```

## Cleanup

```bash
make clean
```

Uninstalls Istio and removes sample apps. Does NOT delete the cluster. Use `REMOVE_CACHE=1` for non-interactive cache removal.

## Troubleshooting

### Missing prerequisites (bare metal)

If `make create-baremetal` reports missing kubeadm, containerd, swap, etc.:

```bash
sudo ./scripts/install-baremetal-prereqs.sh
```

See [Bare Metal Deployment](docs/BAREMETAL.md) for full prerequisites.

### HTTP proxy warnings (kubeadm behind corporate proxy)

If kubeadm reports proxy warnings for 10.96.0.0/12 or 192.168.0.0/16:

```bash
export NO_PROXY="localhost,127.0.0.1,10.96.0.0/12,192.168.0.0/16"
# Add control-plane/node IPs: NO_PROXY="${NO_PROXY},10.200.15.195"
make create-baremetal
```

Or set in `config/local.sh`.

### kubeadm init failed (experimental API, etc.)

If a previous `kubeadm init` ran partially, reset first:

```bash
sudo kubeadm reset -f
make create-baremetal
```

### Cannot reach cluster

Create a cluster first: `make create-baremetal` (bare metal), or use minikube/kind. Ensure `kubectl cluster-info` succeeds.

### Istio platform

For GKE, EKS, k3d, minikube: set `ISTIO_PLATFORM` (e.g. `gke`, `eks`, `k3d`, `minikube`).

### ztunnel not ready

```bash
kubectl get pods -n istio-system -l app=ztunnel
kubectl logs -n istio-system -l app=ztunnel
```

### Sample app not reachable

Ensure `grimlock` has label `istio.io/dataplane-mode=ambient`.

## Docs

- [Bare Metal Deployment](docs/BAREMETAL.md)
- [Directory Structure](docs/STRUCTURE.md)
