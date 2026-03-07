# ztunnel-testbed

A production-oriented testbed for **Istio ambient mode** and **ztunnel** on Kubernetes. Supports single-node and multi-node bare metal (kubeadm), comprehensive functionality tests, and performance benchmarks.

## Features

- **Kubernetes**: Existing cluster or bare metal (kubeadm, single-node or multi-node)
- **CNI**: Calico (default) or Cilium (no Helm, Cilium CLI)
- **Istio ambient**: Installed via `istioctl`
- **Gateway API CRDs**: For traffic routing
- **Sample apps**: http-echo + curl-client in `grimlock` (ambient) and `grimlock-baseline` (non-ambient)
- **Multi-node apps**: Node-pinned pods for cross-node ztunnel HBONE tunnel testing
- **17 functionality tests**: Interactive menu, filter by name, or run all
- **Performance suite**: Throughput by payload size, P99 latency, HTTP benchmarks, concurrency sweep
- **Inspection**: ztunnel workloads, logs, certificates, config

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
make test-func              # interactive menu: pick which tests to run
make test-func TEST=--all   # run all tests non-interactively
make test-perf              # full performance suite
make bench-quick            # quick performance check (5s per test)
```

### Option B: Bare metal - single node (control-plane runs workloads)

```bash
# 0. Install prerequisites (one-time)
sudo ./scripts/install-baremetal-prereqs.sh

# 1. Create cluster (control-plane also runs pods)
make create-baremetal

# 2. Install Istio + deploy sample apps
make setup

# 3. Run tests
make test-func              # interactive menu
make test-perf              # performance benchmarks
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
make test-func                              # interactive menu
make test-func TEST=ztunnel-cross-node      # cross-node HBONE tunnel test only
make test-func TEST=ztunnel-local           # same-node ztunnel test only
make test-perf                              # performance benchmarks
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
| 3 | `make deploy` | Deploy sample apps (+ cross-node apps if multi-node) |
| 4 | `make test-func` | Run functionality tests (interactive) |
| 5 | `make test-perf` | Run performance benchmarks |

**Note**: `make create` only verifies connectivity. It does not create a cluster. Use `make create-baremetal` to create a cluster on bare metal.

## Make Targets

### Setup

| Target | Description |
|--------|-------------|
| `make setup` | Verify cluster + install Istio + deploy apps |
| `make create` | Verify kubectl cluster connectivity |
| `make create-baremetal` | Create single-node cluster on bare metal (kubeadm) |
| `make create-baremetal-multi WORKER=10.136.0.75` | Create multi-node cluster |
| `make install-prereqs-baremetal` | Print install command for bare metal deps |
| `make install` | Install Istio ambient only |
| `make install-cilium` | Install Cilium CNI (no Helm, Istio compatible) |
| `make deploy` | Deploy sample apps (+ cross-node apps if multi-node) |

### Functionality Tests

| Target | Description |
|--------|-------------|
| `make test-func` | Interactive menu (pick tests to run) |
| `make test-func TEST=--all` | Run all 17 functionality tests (CI-friendly) |
| `make test-func TEST=pod` | Run tests matching "pod" |
| `make test-func TEST=ztunnel` | Run all ztunnel tests |
| `make test-list` | List available tests |

### Performance Tests

| Target | Description |
|--------|-------------|
| `make test-perf` | Interactive menu (pick benchmark type and topology) |
| `make bench-throughput` | Throughput test (single-node) |
| `make bench-latency` | Latency test (single-node) |
| `make bench-throughput-cross` | Throughput test (cross-node, multi-node) |
| `make bench-latency-cross` | Latency test (cross-node, multi-node) |
| `make bench-ambient` | All benchmarks (ambient only) |
| `make bench-baseline` | All benchmarks (baseline only) |
| `make bench-quick` | Quick benchmark (5s, no sweep) |

### Other

| Target | Description |
|--------|-------------|
| `make build-images` | Build local http-echo, curl-client, fortio images |
| `make load-images` | Load local images into kind/minikube |
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
│   ├── cluster.sh           # KUBE_CONTEXT, APP_NAMESPACE
│   ├── baremetal.sh         # Bare metal: CNI, K8S_VERSION, WORKER_NODES
│   ├── images.sh            # Container images (upstream or local)
│   ├── cilium.sh            # Cilium version
│   ├── kubeadm-config.yaml.template
│   ├── local.sh.example     # Template for overrides
│   └── local.sh             # (gitignored) Your overrides
├── manifests/
│   ├── sample-apps/
│   │   ├── simple-http-server.yaml.template     # http-echo + curl-client
│   │   └── cross-node-apps.yaml.template        # Node-pinned pods (multi-node)
│   ├── sample-apps-baseline/
│   │   └── http-echo-baseline.yaml.template
│   ├── performance/
│   │   └── fortio-client.yaml.template
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
│   ├── cleanup.sh
│   └── baremetal/
│       ├── join-worker.sh
│       └── setup-worker.sh       # Auto-install prereqs + join via SSH
├── tests/
│   ├── lib.sh                    # Test helpers: pass/fail/skip/detail + timing
│   ├── functionality/            # 17 test scripts (auto-discovered)
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
│   │   ├── test-ztunnel-local.sh         # Same-node ztunnel test
│   │   ├── test-ztunnel-cross-node.sh    # Cross-node HBONE tunnel test
│   │   └── test-mtls-policy.sh
│   └── performance/
│       └── run-bench.sh          # Throughput, latency, HTTP benchmarks
├── docs/
│   ├── BAREMETAL.md
│   ├── TESTING.md
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

# Bare metal
CNI_PROVIDER="cilium"                  # calico (default) | cilium
CILIUM_VERSION="1.16.0"

# Multi-node (auto-join workers via SSH)
WORKER_NODES="10.136.0.75"            # comma-separated worker IPs
WORKER_SSH_USER="gsadmin"             # SSH user for worker nodes
```

## Functionality Tests

Run interactively to pick specific tests, or run all at once:

```bash
make test-func                  # interactive menu
make test-func TEST=--all       # run all (CI-friendly)
make test-func TEST=ztunnel     # run tests matching "ztunnel"
make test-func TEST=pod-to-pod  # run a single test
make test-list                  # list all available tests
```

### Infrastructure tests (no sample apps needed)

| Test | Description |
|------|-------------|
| test-cluster-ready | All nodes Ready. Shows each node's status. |
| test-cni-ready | istio-cni-node DaemonSet fully rolled out on all nodes. |
| test-gateway-api | Gateway API CRDs (Gateway, HTTPRoute) installed. |
| test-istiod-ready | Istiod control plane running with version info. |
| test-ztunnel-ready | ztunnel DaemonSet ready on all nodes with image version. |
| test-ztunnel-certs | ztunnel has active SPIFFE mTLS certificates. |
| test-ztunnel-logs | ztunnel not crash-looping, no FATAL/panic in logs. |

### Application tests (need `make deploy`)

| Test | Description |
|------|-------------|
| test-namespace-ambient | `grimlock` namespace has `istio.io/dataplane-mode=ambient`. |
| test-ambient-vs-baseline | `grimlock` has ambient, `grimlock-baseline` does not. Both have pods. |
| test-sample-app-running | http-echo and curl-client deployments have ready pods. |
| test-dns-resolution | CoreDNS resolves `kubernetes.default` and `http-echo` from inside pods. |
| test-pod-to-pod | curl-client → http-echo pod IP (direct, through ztunnel). |
| test-pod-to-service | curl-client → http-echo ClusterIP Service (DNS + ztunnel). |
| test-ztunnel-workloads | `istioctl ztunnel-config workloads` shows grimlock workloads. |
| test-ztunnel-local | Same-node pod-to-pod through ztunnel + proxy log verification. |
| test-ztunnel-cross-node | Cross-node HBONE tunnel with encryption evidence (multi-node only). |
| test-mtls-policy | mTLS encryption proof: SPIFFE certs, HBONE protocol, ztunnel interception, metrics. |

See [Functionality Testing Guide](docs/TESTING.md) for full documentation.

## Performance Tests

Comprehensive benchmark suite using **fortio** with a dedicated client/server architecture. Separate **throughput** and **latency** tests, each with **single-node** and **cross-node** (multi-node) variants.

### Test architecture

```
Single-node:
  fortio-client  →  ztunnel (local mTLS)  →  fortio-server     (same node)

Cross-node (multi-node):
  fortio-client (node1)  →  ztunnel HBONE tunnel  →  fortio-server (node2)

Baseline (no mesh):
  fortio-client  →  fortio-server  (direct, no ztunnel)
```

### Interactive mode

Running `make test-perf` shows an interactive menu:

```
Performance Benchmarks
─────────────────────────────────────────

  Cluster: grimlock-cell (2 node(s))

  Single-node tests:
    1) Throughput test (payload sizes + concurrency sweep)
    2) Latency test (P50/P90/P99/P99.9 in microseconds)
    3) Both throughput + latency

  Cross-node tests (multi-node):
    4) Throughput test (cross-node HBONE tunnel)
    5) Latency test (cross-node HBONE tunnel)
    6) Both throughput + latency (cross-node)

  Comparison:
    7) Ambient only (all benchmarks)
    8) Baseline only (all benchmarks)
    9) Quick benchmark (5s per test, skip sweep)

    0) Run ALL benchmarks (auto-detect topology)

Select benchmark [0-9]:
```

### Benchmark categories

| Category | Throughput test | Latency test |
|----------|----------------|--------------|
| **Payload sizes** | Max QPS for 64-1500B POST | P50/P90/P99/P99.9 in microseconds |
| **HTTP methods** | GET, POST, burst c=32/64 | GET c=1, no-keepalive c=1, POST c=1, GET c=4/16/64 |
| **Concurrency sweep** | QPS at c=1,4,8,16,32,64,128 | Latency at c=1,4,16,64 |
| **ztunnel resources** | CPU/memory before and after | CPU/memory before and after |
| **Ambient vs baseline** | Both modes compared | Both modes compared |

### Make targets

```bash
# Interactive menu
make test-perf

# Specific benchmarks
make bench-throughput               # throughput, single-node
make bench-latency                  # latency, single-node
make bench-throughput-cross         # throughput, cross-node (multi-node)
make bench-latency-cross            # latency, cross-node (multi-node)

# Mode selection
make bench-ambient                  # all benchmarks, ambient only
make bench-baseline                 # all benchmarks, baseline only
make bench-quick                    # quick: 5s per test, skip sweep

# Custom parameters
CONCURRENCY=64 DURATION=60s make bench-throughput
PACKET_SIZES="64,1500" make bench-latency
MODE=ambient TOPOLOGY=cross-node make test-perf
```

### Parameters

| Variable | Default | Description |
|----------|---------|-------------|
| `MODE` | both | `ambient`, `baseline`, or `both` |
| `BENCH` | all | `throughput`, `latency`, or `all` |
| `TOPOLOGY` | local (auto) | `local` (single-node) or `cross-node` (multi-node) |
| `CONCURRENCY` | 4 (throughput) / 1 (latency) | Concurrent connections |
| `DURATION` | 20s | Duration per test |
| `REQUESTS` | 0 (use duration) | Total requests (overrides DURATION) |
| `PACKET_SIZES` | 64,128,256,512,1024,1500 | Payload sizes in bytes |
| `SKIP_SWEEP` | 0 | Set to 1 to skip concurrency sweep |
| `OUTPUT_DIR` | .bench-results | Results directory |

### Sample output (microseconds)

```
========================================================================
  ztunnel-testbed THROUGHPUT Report
  Nodes: 1   Topology: local
  Mode: both  Concurrency: 4  Duration: 20s
========================================================================

  ztunnel resource usage (before ambient):
    ztunnel-mqqb7   12m    45Mi

==================================================================
  THROUGHPUT: Payload Size Sweep (ambient, single-node)
  Path: fortio-client → single-node → fortio-server
  Concurrency: 4, Duration: 20s
==================================================================

  Test                          QPS       Avg(us)   P50(us)   P90(us)   P99(us)  P99.9us   OK%
  ----------------------------  ---------  --------  --------  --------  --------  --------  ------
  64B POST                      8234.5      486.0     412.0     823.0    1567.0    3012.0  100.0 %
  128B POST                     7891.2      507.0     428.0     856.0    1678.0    3245.0  100.0 %
  1500B POST                    5678.9      704.0     593.0    1187.0    2345.0    4567.0  100.0 %

==================================================================
  LATENCY: HTTP Methods (ambient, single-node)
  Concurrency: 1 (low for accurate latency)
==================================================================

  GET (c=1)                     2345.6      426.0     398.0     534.0     789.0    1234.0  100.0 %
  GET no-keepalive (c=1)         456.7     2189.0    1978.0    2923.0    4456.0    7789.0  100.0 %
  POST 1KB (c=1)                2123.4      471.0     423.0     567.0     834.0    1345.0  100.0 %

  ztunnel resource usage (after ambient):
    ztunnel-mqqb7   85m    67Mi
```

Reports saved to `.bench-results/<type>-<topology>-<timestamp>.txt`.

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

Interactive cleanup with four levels:

```bash
make clean                   # interactive menu
make clean CLEAN=apps        # remove sample apps (namespaces grimlock, grimlock-baseline)
make clean CLEAN=istio       # remove apps + Istio + Gateway API CRDs
make clean CLEAN=full        # all above + local cache (.cache, bin, .bench-results)
make clean CLEAN=nuclear     # all above + destroy Kubernetes cluster (kubeadm reset)
```

| Level | What it removes |
|-------|----------------|
| **apps** | Sample app namespaces, rendered manifests |
| **istio** | Apps + Istio (purge) + Gateway API CRDs + istio-system namespace |
| **full** | Istio + local cache, binaries, bench results |
| **nuclear** | Full + kubeadm reset, kubeconfig, kubectl wrapper, bashrc entries, sudoers drop-in |

## Troubleshooting

### Missing prerequisites (bare metal)

If `make create-baremetal` reports missing kubeadm, containerd, swap, etc.:

```bash
sudo ./scripts/install-baremetal-prereqs.sh
```

See [Bare Metal Deployment](docs/BAREMETAL.md) for full prerequisites.

### HTTP proxy / corporate firewall

The testbed handles corporate proxies automatically:
- `create-cluster-baremetal.sh` configures `NO_PROXY` for cluster CIDRs and installs a kubectl wrapper
- Containerd proxy is configured via systemd drop-in when `HTTP_PROXY` is set
- `sudo kubectl` works through the proxy-bypass wrapper at `/usr/local/bin/kubectl`

If kubeadm reports proxy warnings:

```bash
export NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
export HTTP_PROXY="http://dcproxy.simulprod.com:3128"
export HTTPS_PROXY="$HTTP_PROXY"
make create-baremetal
```

### kubectl connects to localhost:8080 (connection refused)

kubectl falls back to `http://localhost:8080` when it has no valid kubeconfig.

**Auto-fix**: Scripts using `ensure_kubectl_context` automatically fix this by switching to `~/.kube/config` or copying from `/etc/kubernetes/admin.conf`.

**Manual fix (on control-plane)**:
```bash
unset KUBECONFIG
sudo cp -f /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl cluster-info
```

### Node not Ready / CNI not initialized

If the node stays NotReady after cluster creation, the CNI config may not have been picked up:

```bash
sudo systemctl restart containerd
# Wait 30s, then check:
kubectl get nodes
```

### Performance test shows "FAILED" or no data

1. Check fortio pod: `kubectl get pods -n grimlock -l app=fortio`
2. Test connectivity: `kubectl exec -n grimlock <fortio-pod> -c fortio -- fortio curl http://http-echo.grimlock:80/`
3. Check fortio version: `kubectl exec -n grimlock <fortio-pod> -c fortio -- fortio version`

### Choke points and logging

Scripts emit `[HH:MM:SS] [PHASE]` logs with duration for long-running steps:

| Phase | Script | Typical duration | Likely cause if slow |
|-------|--------|------------------|----------------------|
| KUBEADM | create-baremetal | 2-5 min | Image pull (registry.k8s.io), proxy |
| WORKER | create-baremetal | 1-3 min per worker | SSH + prereqs install + join |
| CILIUM / CALICO | create-baremetal | 1-3 min | CNI image pull, network |
| ISTIOCTL | install-istio | 1-3 min | Download from GitHub |
| ISTIO | install-istio | 2-5 min | Istio image pull |
| ZTUNNEL | install-istio | 1-2 min | DaemonSet rollout |
| ROLLOUT | deploy | 1-3 min | Image pull, pod scheduling |
| BENCH | test-perf | 15s per test | fortio load generation |

## Docs

- [Bare Metal Deployment](docs/BAREMETAL.md)
- [Functionality Testing Guide](docs/TESTING.md)
- [Directory Structure](docs/STRUCTURE.md)
