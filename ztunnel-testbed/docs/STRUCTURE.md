# ztunnel-testbed Directory Structure

## Overview

```
ztunnel-testbed/
├── config/
├── manifests/
├── scripts/
├── scripts/baremetal/
├── tests/
├── docs/
├── Makefile
└── README.md
```

## config/

| File | Description |
|------|-------------|
| `versions.sh` | Istio, Gateway API version variables |
| `cluster.sh` | KUBE_CONTEXT, APP_NAMESPACE, APP_NAMESPACE_BASELINE |
| `images.sh` | HTTP_ECHO_IMAGE, CURL_IMAGE, FORTIO_IMAGE (USE_LOCAL_IMAGES, IMAGE_REGISTRY) |
| `baremetal.sh` | Bare metal: CNI_PROVIDER, K8S_VERSION, POD_NETWORK_CIDR, CALICO_VERSION |
| `cilium.sh` | Cilium version (when CNI_PROVIDER=cilium) |
| `kubeadm-config.yaml` | kubeadm ClusterConfiguration |
| `kubeadm-config.yaml.template` | Template with env var substitution |
| `local.sh.example` | Template for local overrides |
| `local.sh` | Local overrides (gitignored, create manually) |

## manifests/

| Path | Description |
|------|-------------|
| `namespace-ambient.yaml` | Namespace with ambient label |
| `sample-apps/simple-http-server.yaml.template` | Ambient mesh apps (envsubst: HTTP_ECHO_IMAGE, CURL_IMAGE, APP_NAMESPACE) |
| `sample-apps-baseline/http-echo-baseline.yaml.template` | Non-ambient apps (envsubst) |
| `performance/fortio-client.yaml.template` | fortio load generator (envsubst) |
| `cni/calico-custom-resources.yaml` | Calico Installation CR (pod CIDR) |

## scripts/

| Script | Description |
|--------|-------------|
| `common.sh` | Shared helpers (log, check_cmd, ensure_kubectl_context) |
| `create-cluster.sh` | Verify kubectl cluster connectivity |
| `create-cluster-baremetal.sh` | Create K8s cluster on bare metal (kubeadm, Calico or Cilium) |
| `install-baremetal-prereqs.sh` | Install kubeadm, kubelet, kubectl, containerd (Ubuntu/Debian) |
| `build-images.sh` | Build local http-echo, curl-client, fortio images |
| `load-images.sh` | Load local images into kind/minikube |
| `install-istio.sh` | Install Istio ambient (istioctl) |
| `install-cilium.sh` | Install Cilium CNI (Cilium CLI, no Helm) |
| `deploy-sample-apps.sh` | Deploy sample apps to grimlock + grimlock-baseline |
| `run-functionality-tests.sh` | Run functionality tests |
| `run-performance-tests.sh` | Run performance tests |
| `ztunnel-inspect.sh` | Inspect ztunnel (workloads, pods, logs, certs) |
| `setup-all.sh` | One-click: create + install + deploy |
| `cleanup.sh` | Uninstall Istio, remove sample apps, optional cache |

## scripts/baremetal/

| Script | Description |
|--------|-------------|
| `join-worker.sh` | Join worker node to cluster (kubeadm join) |

## tests/

| Path | Description |
|------|-------------|
| `lib.sh` | Test helpers (test_start, pass, fail, test_summary) |
| `functionality/test-*.sh` | Functionality test cases |
| `performance/run-bench.sh` | Performance benchmark (fortio/curl) |

## Environment Variables

| Variable | Config | Description |
|----------|--------|-------------|
| `ISTIO_VERSION` | versions.sh | Istio version |
| `GATEWAY_API_VERSION` | versions.sh | Gateway API CRDs version |
| `KUBE_CONTEXT` | cluster.sh | kubectl context to use |
| `APP_NAMESPACE` | cluster.sh | Sample app namespace (default: grimlock) |
| `APP_NAMESPACE_BASELINE` | cluster.sh | Baseline namespace (default: grimlock-baseline) |
| `ISTIO_PLATFORM` | local.sh | gke, eks, k3d, minikube |
| `CNI_PROVIDER` | baremetal.sh | calico \| cilium |
| `CILIUM_VERSION` | cilium.sh | Cilium version |
| `K8S_VERSION` | baremetal.sh | Kubernetes version for kubeadm |
| `POD_NETWORK_CIDR` | baremetal.sh | Pod network CIDR |
| `RECREATE` | - | Force recreate (bare metal) |
| `REMOVE_CACHE` | - | Non-interactive cache cleanup |
| `MODE` | - | ambient \| baseline \| both (perf) |
| `CONCURRENCY`, `REQUESTS`, `DURATION` | - | Performance test params |
