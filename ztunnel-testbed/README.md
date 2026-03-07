# ztunnel-testbed

A production-oriented, complete testbed for **Istio ambient mode** and **ztunnel** on a Kubernetes cluster. Uses an existing cluster (kubectl-configured). Supports one-click setup, functionality tests, and performance benchmarks.

## Features

- **Kubernetes cluster**: Existing cluster or bare metal (kubeadm, no k3s)
- **Cilium CNI**: Optional, Istio ambient compatible (cni.exclusive=false, socketLB.hostNamespaceOnly=true), no Helm
- **Istio ambient mode**: Installed via `istioctl`
- **Gateway API CRDs**: Installed for traffic routing
- **Sample apps**: http-echo + curl-client (ambient) + baseline (non-ambient) for comparison
- **Functionality tests**: Cluster, Istio, ztunnel, Pod-to-Pod, Service, ztunnel visibility
- **Performance tests**: fortio/curl-based, ambient vs baseline comparison
- **Inspection**: Scripts to view ztunnel workloads, logs, config

## Prerequisites

- **Kubernetes cluster** (any: GKE, EKS, AKS, kind, minikube, etc.)
- **kubectl** configured to reach the cluster
- **curl** (for Istio download)

## Quick Start

```bash
# Ensure kubectl points to your cluster, then:
make setup

# Run functionality tests
make test-func

# Run performance tests (ambient vs baseline)
make test-perf
```

Or step by step:

```bash
./scripts/create-cluster.sh
./scripts/install-istio.sh
./scripts/deploy-sample-apps.sh
./scripts/run-functionality-tests.sh
./scripts/run-performance-tests.sh
```

### Bare Metal (kubeadm)

Create a standard K8s cluster on bare metal with kubeadm (no k3s). See [docs/BAREMETAL.md](docs/BAREMETAL.md):

```bash
# Run on control-plane node (default: Calico CNI)
make create-baremetal

# Use Cilium as CNI (no Helm, uses Cilium CLI)
CNI_PROVIDER=cilium make create-baremetal

# Run kubeadm join on each worker (command is printed in output)
```

### Cilium CNI

Install Cilium on an existing cluster (Istio ambient compatible, no Helm):

```bash
make install-cilium
# or
./scripts/install-cilium.sh
```

Remove existing CNI (e.g. Calico) before installing Cilium.

## Directory Structure

```
ztunnel-testbed/
├── config/
│   ├── versions.sh       # Version vars (Istio, Gateway API)
│   ├── cluster.sh        # KUBE_CONTEXT (optional)
│   ├── local.sh.example  # Template for local overrides
│   └── local.sh          # (gitignored) Your overrides
├── manifests/
│   ├── namespace-ambient.yaml
│   ├── sample-apps/           # Ambient mesh apps
│   │   └── simple-http-server.yaml
│   ├── sample-apps-baseline/  # Non-ambient for perf comparison
│   │   └── http-echo-baseline.yaml
│   └── performance/
│       └── fortio-client.yaml
├── scripts/
│   ├── common.sh
│   ├── create-cluster.sh
│   ├── create-cluster-baremetal.sh   # kubeadm on bare metal
│   ├── install-istio.sh
│   ├── install-cilium.sh   # Cilium CNI (no Helm)
│   ├── deploy-sample-apps.sh
│   ├── run-functionality-tests.sh
│   ├── run-performance-tests.sh
│   ├── ztunnel-inspect.sh
│   ├── setup-all.sh
│   └── cleanup.sh
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
│   │   └── test-ztunnel-workloads.sh
│   └── performance/
│       └── run-bench.sh
├── Makefile
└── README.md
```

## Configuration

### Version Overrides

Edit `config/local.sh` (copy from `config/local.sh.example`):

```bash
ISTIO_VERSION="1.29.0"
GATEWAY_API_VERSION="v1.4.0"
KUBE_CONTEXT="my-context"   # optional
```

Or set environment variables:

```bash
export ISTIO_VERSION=1.30.0
./scripts/install-istio.sh
```

### Cluster Config

Use any Kubernetes cluster. Set `KUBE_CONTEXT` in `config/local.sh` to use a specific kubectl context. Otherwise the current context is used.

## Functionality Tests

| Test | Description |
|------|-------------|
| test-cluster-ready | All nodes Ready |
| test-gateway-api | Gateway API CRDs installed |
| test-istiod-ready | Istiod deployment ready |
| test-ztunnel-ready | ztunnel DaemonSet ready on all nodes |
| test-namespace-ambient | sample-apps has ambient label |
| test-sample-app-running | http-echo and curl-client running |
| test-pod-to-pod | Pod → Pod IP (direct, via ztunnel) |
| test-pod-to-service | Pod → Service → Pod |
| test-ztunnel-workloads | `istioctl ztunnel-config workloads` |

## Performance Tests

**Tools**: fortio (preferred), or curl loop fallback.

**Modes**:

- `MODE=ambient` – traffic via ztunnel (sample-apps)
- `MODE=baseline` – traffic without ztunnel (sample-apps-baseline)
- `MODE=both` (default) – run both for comparison

**Parameters** (environment):

```bash
CONCURRENCY=8 REQUESTS=10000 DURATION=30s ./scripts/run-performance-tests.sh
```

**Output**: `.bench-results/<mode>-<timestamp>.txt`

### Performance Test Caveats

This is a **demo benchmark** for local development, not a production-grade benchmark:

- Runs on a laptop/VM with limited resources
- Single-node or few-node topology
- No realistic network latency or congestion
- Results depend on Docker, host CPU, and load

Use for **relative comparison** (ambient vs baseline) and quick regression checks, not for capacity planning.

## Inspecting ztunnel

```bash
./scripts/ztunnel-inspect.sh all         # workloads, pods, logs
./scripts/ztunnel-inspect.sh workloads   # istioctl ztunnel-config workloads
./scripts/ztunnel-inspect.sh pods
./scripts/ztunnel-inspect.sh logs 100
./scripts/ztunnel-inspect.sh certificates
```

## Cleanup

```bash
make clean
# or
./scripts/cleanup.sh
```

Prompts to remove local cache (Istio download, benchmark results). Use `REMOVE_CACHE=1` for non-interactive cleanup.

**Note**: Cleanup uninstalls Istio and removes sample apps. It does NOT delete the Kubernetes cluster.

## Troubleshooting

### Istio CNI / Platform

For GKE, EKS, k3d, or minikube, set `ISTIO_PLATFORM` (e.g. `gke`, `eks`, `k3d`, `minikube`). For standard Kubernetes the default works. See [Istio platform prerequisites](https://istio.io/latest/docs/ambient/install/platform-prerequisites/).

### ztunnel not ready

```bash
kubectl get pods -n istio-system -l app=ztunnel
kubectl describe daemonset ztunnel -n istio-system
kubectl logs -n istio-system -l app=ztunnel
```

### Sample app not reachable

Ensure `sample-apps` has label `istio.io/dataplane-mode=ambient`:

```bash
kubectl get ns sample-apps -o yaml | grep dataplane-mode
```

---

**License**: Apache 2.0 (or project default)
