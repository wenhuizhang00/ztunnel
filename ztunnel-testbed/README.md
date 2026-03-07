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
make test-func          # interactive menu: pick which tests to run
make test-func TEST=--all   # run all tests non-interactively
make test-perf
```

### Option B: Bare metal - single node (control-plane runs workloads)

```bash
# 0. Install prerequisites (one-time)
sudo ./scripts/install-baremetal-prereqs.sh

# 1. Create cluster (control-plane also runs pods)
make create-baremetal

# 2. Install Istio + deploy sample apps + run tests
make setup
make test-func
```

### Option B2: Bare metal - multi-node (control-plane + worker)

```bash
# 0. On control-plane: install prerequisites
sudo ./scripts/install-baremetal-prereqs.sh

# 1. Create cluster with worker node(s) (auto-installs prereqs + joins via SSH)
WORKER_NODES="10.136.0.75" make create-baremetal

# 2. Install Istio + deploy sample apps (includes cross-node test pods)
make setup

# 3. Run tests (includes same-node AND cross-node ztunnel tests)
make test-func
make test-func TEST=ztunnel-cross-node   # cross-node HBONE tunnel test
make test-func TEST=ztunnel-local        # same-node ztunnel test
```

Worker nodes are set up automatically via SSH. Requirements:
- SSH key access from control-plane to worker: `ssh gsadmin@10.136.0.75`
- Worker has passwordless sudo
- Set `WORKER_SSH_USER` if SSH user differs from current user

For multiple workers: `WORKER_NODES="10.136.0.75,10.136.0.76" make create-baremetal`

### Option C: Other cluster tools (minikube, kind, etc.)

```bash
# Create cluster with your preferred tool, then:
kubectl cluster-info

# Full setup: verify cluster, install Istio, deploy sample apps
make setup

# Run tests
make test-func
make test-perf
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
| `make test-func` | Interactive test menu (pick tests to run) |
| `make test-func TEST=--all` | Run all functionality tests |
| `make test-func TEST=pod` | Run tests matching "pod" |
| `make test-list` | List available functionality tests |
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
│   ├── cluster.sh           # KUBE_CONTEXT (default: grimlock-cell)
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
│   ├── lib.sh                          # Test helpers: pass/fail/skip/detail
│   ├── functionality/
│   │   ├── test-cluster-ready.sh
│   │   ├── test-cni-ready.sh
│   │   ├── test-gateway-api.sh
│   │   ├── test-istiod-ready.sh
│   │   ├── test-ztunnel-ready.sh
│   │   ├── test-ztunnel-certs.sh
│   │   ├── test-ztunnel-logs.sh
│   │   ├── test-ztunnel-workloads.sh
│   │   ├── test-namespace-ambient.sh
│   │   ├── test-ambient-vs-baseline.sh
│   │   ├── test-sample-app-running.sh
│   │   ├── test-dns-resolution.sh
│   │   ├── test-pod-to-pod.sh
│   │   ├── test-pod-to-service.sh
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
KUBE_CONTEXT="grimlock-cell"   # Default; override if your context has a different name

# Istio platform (GKE, EKS, k3d, minikube)
ISTIO_PLATFORM="gke"

# Bare metal CNI
CNI_PROVIDER="cilium"       # calico (default) | cilium
CILIUM_VERSION="1.16.0"
```

## Functionality Tests

Run interactively to pick specific tests, or run all at once:

```bash
make test-func                  # interactive menu
make test-func TEST=--all       # run all
make test-func TEST=ztunnel     # run tests matching "ztunnel"
make test-func TEST=pod-to-pod  # run a single test
make test-list                  # list all available tests
```

| Test | Description |
|------|-------------|
| test-cluster-ready | All nodes Ready |
| test-cni-ready | istio-cni-node DaemonSet ready |
| test-gateway-api | Gateway API CRDs installed |
| test-istiod-ready | Istiod deployment ready |
| test-ztunnel-ready | ztunnel DaemonSet ready |
| test-ztunnel-certs | ztunnel mTLS certificates active |
| test-ztunnel-logs | ztunnel healthy (no crash loops/panics) |
| test-ztunnel-workloads | `istioctl ztunnel-config workloads` |
| test-namespace-ambient | grimlock has ambient label |
| test-ambient-vs-baseline | Ambient vs non-ambient namespace isolation |
| test-sample-app-running | http-echo and curl-client running |
| test-dns-resolution | In-cluster DNS resolves service names |
| test-pod-to-pod | Pod → Pod IP (via ztunnel) |
| test-pod-to-service | Pod → Service → Pod |
| test-ztunnel-local | Same-node pod-to-pod through ztunnel (local path) |
| test-ztunnel-cross-node | Cross-node pod-to-pod through HBONE tunnel (multi-node only) |
| test-mtls-policy | mTLS/policy placeholder (extend as needed) |

## Performance Tests

Comprehensive benchmark suite measuring throughput, P99 latency, and HTTP application performance.

### Test matrix

| Benchmark | What it measures |
|-----------|-----------------|
| **Throughput by payload size** | QPS and Mbps for 64, 128, 256, 512, 1024, 1500 byte payloads |
| **P99 latency by payload size** | Avg, P50, P90, P99, P99.9 latency per payload size |
| **HTTP application benchmark** | GET, GET (no keep-alive), POST 1KB, high-concurrency burst |
| **Concurrency sweep** | QPS vs latency at c=1,2,4,8,16,32,64 |
| **Ambient vs baseline** | All above run for both modes; compare mTLS overhead |

### Running

```bash
make test-perf                         # full suite: ambient + baseline comparison
make bench-ambient                     # ambient only
make bench-baseline                    # baseline only
make bench-quick                       # quick run (5s, skip concurrency sweep)

# Custom params
CONCURRENCY=8 DURATION=30s make test-perf
PACKET_SIZES="64,1500" SKIP_SWEEP=1 make bench-ambient
```

### Parameters

| Variable | Default | Description |
|----------|---------|-------------|
| `MODE` | both | ambient, baseline, or both |
| `CONCURRENCY` | 4 | Concurrent connections |
| `DURATION` | 15s | Per-test duration |
| `REQUESTS` | 0 (use duration) | Total requests per test |
| `PACKET_SIZES` | 64,128,256,512,1024,1500 | Comma-separated payload sizes in bytes |
| `SKIP_SWEEP` | 0 | Set to 1 to skip concurrency sweep |
| `OUTPUT_DIR` | .bench-results | Results directory |

### Output

Results are saved to `.bench-results/report-<timestamp>.txt` with formatted tables:

```
==================================================================
  Throughput & Latency by Payload Size (ambient)
  Concurrency: 4, Duration: 15s
==================================================================

  Test                                     QPS       Avg        P50        P90        P99      P99.9  Throughput
  64B payload                           12345.6    0.324ms    0.298ms    0.512ms    1.234ms    2.567ms  6.32Mbps
  128B payload                          11234.5    0.356ms    0.315ms    0.534ms    1.345ms    2.789ms  11.51Mbps
  ...
```

Demo benchmarks for relative comparison; not for production capacity planning.

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

If kubeadm reports proxy warnings for 10.200.15.195 or cluster CIDRs:

```bash
# Exclude private ranges and your control-plane IP from proxy
export NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.200.15.195"
export no_proxy="${NO_PROXY}"
make create-baremetal
```

The script auto-adds node IP and CIDRs; extend in `config/local.sh` if needed.

**Note**: `ping http://proxy.example.com:3128` won't work (ping uses ICMP, not HTTP). Use `curl -x http://proxy:3128 -I https://example.com` to test proxy.

### Image pull timeout (registry.k8s.io dial tcp i/o timeout)

Containerd does **not** use the shell's `HTTP_PROXY`. Configure proxy for containerd before `make create-baremetal`:

```bash
export HTTP_PROXY="http://dcproxy.simulprod.com:3128"
export HTTPS_PROXY="$HTTP_PROXY"
export NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

# If containerd was already installed without proxy, the script will add it and restart
make create-baremetal
```

Or set in `config/local.sh` and `CONTAINERD_HTTP_PROXY` for the install-prereqs step.

### kubeadm init failed (experimental API, etc.)

If a previous `kubeadm init` ran partially, reset first:

```bash
sudo kubeadm reset -f
make create-baremetal
```

### kubectl connects to localhost:8080 (connection refused)

**Root cause**: kubectl falls back to `http://localhost:8080` when it has no valid kubeconfig. Common causes:

| Cause | Where it's set | Fix |
|-------|----------------|-----|
| `KUBECONFIG` points to non-existent file | `config/local.sh`, `~/.bashrc`, `~/.profile` | `unset KUBECONFIG` or remove/fix the line |
| `~/.kube/config` missing on control-plane | — | `sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config` |
| KUBECONFIG points to non-existent file | `config/local.sh` or shell profile | Use `~/.kube/config`; remove bad KUBECONFIG from config/local.sh |

**Built-in auto-fix**: Scripts that use `ensure_kubectl_context` (e.g. `make setup`, `make create`) automatically:
- Switch to `~/.kube/config` when `KUBECONFIG` points to a non-existent file
- Copy `/etc/kubernetes/admin.conf` to `~/.kube/config` when on control-plane and config is missing (may prompt for sudo)

**Manual fix (on control-plane)**:
```bash
unset KUBECONFIG
mkdir -p ~/.kube
sudo cp -f /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl cluster-info
```

**If it persists**: Check shell profile — `grep -n KUBECONFIG ~/.bashrc ~/.profile 2>/dev/null`. Remove or fix any line that sets `KUBECONFIG` to a path that doesn't exist. Use `~/.kube/config` as the standard path.

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

### Choke points and logging

Scripts emit `[HH:MM:SS] [PHASE]` logs with duration for long-running steps. Typical choke points:

| Phase | Script | Typical duration | Likely cause if slow |
|-------|--------|------------------|----------------------|
| KUBEADM | create-baremetal | 2-5 min | Image pull (registry.k8s.io), proxy |
| CILIUM / CALICO | create-baremetal | 1-3 min | CNI image pull, network |
| ISTIOCTL | install-istio | 1-3 min | Download from istio.io |
| GATEWAY-API | install-istio | 30-60s | Fetch CRD manifest |
| ISTIO | install-istio | 2-5 min | Istio image pull |
| ZTUNNEL | install-istio | 1-2 min | DaemonSet rollout |
| ROLLOUT | deploy | 1-3 min | Image pull, pod scheduling |
| BUILD | build-images | 1-5 min | Base image pull, compile |

Use timestamps to see where time is spent; adjust proxy or pre-pull images if needed.

## Docs

- [Bare Metal Deployment](docs/BAREMETAL.md)
- [Functionality Testing Guide](docs/TESTING.md)
- [Directory Structure](docs/STRUCTURE.md)
