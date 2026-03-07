# ztunnel-testbed Directory Structure

## Overview

```
ztunnel-testbed/
├── config/           # Configuration
├── manifests/        # Kubernetes YAML
├── scripts/          # Executable scripts
├── tests/            # Functionality and performance tests
├── docs/             # Documentation
├── Makefile
└── README.md
```

## config/

| File | Description |
|------|-------------|
| `versions.sh` | Istio, Gateway API version variables |
| `cluster.sh` | KUBE_CONTEXT (optional) |
| `local.sh.example` | Template for local overrides |
| `local.sh` | Local overrides (gitignored, create manually) |

## manifests/

| Dir/File | Description |
|----------|-------------|
| `namespace-ambient.yaml` | Namespace example with ambient label |
| `sample-apps/` | Ambient mesh apps (http-echo + curl-client) |
| `sample-apps-baseline/` | Non-ambient apps for performance comparison |
| `performance/fortio-client.yaml` | fortio load generator client |

## scripts/

| Script | Description |
|--------|-------------|
| `common.sh` | Shared helpers (log, check_cmd, ensure_kubectl_context) |
| `create-cluster.sh` | Verify kubectl cluster connectivity |
| `create-cluster-baremetal.sh` | Create K8s cluster on bare metal with kubeadm (no k3s) |
| `install-istio.sh` | Install Istio ambient mode (istioctl) |
| `install-cilium.sh` | Install Cilium CNI (no Helm) |
| `deploy-sample-apps.sh` | Deploy sample apps (ambient + baseline) |
| `run-functionality-tests.sh` | Run functionality tests |
| `run-performance-tests.sh` | Run performance tests |
| `ztunnel-inspect.sh` | Inspect ztunnel state (workloads, logs, certs) |
| `setup-all.sh` | One-click: create + install + deploy |
| `cleanup.sh` | Uninstall Istio, remove sample apps, optional cache |

## tests/

| Path | Description |
|------|-------------|
| `lib.sh` | Test helpers (test_start, pass, fail, test_summary) |
| `functionality/test-*.sh` | Functionality test cases |
| `performance/run-bench.sh` | Performance benchmark (fortio/curl) |

## Environment variables

- `ISTIO_VERSION`, `GATEWAY_API_VERSION`, etc.: see `config/versions.sh`, `config/cluster.sh`
- `RECREATE=1`: Force recreate existing cluster
- `REMOVE_CACHE=1`: Remove cache in non-interactive cleanup
- `MODE=ambient|baseline|both`: Performance test mode
- `CONCURRENCY`, `REQUESTS`, `DURATION`: Performance test parameters
