# ztunnel

This repository includes **ztunnel-testbed** — a Kubernetes environment to exercise **Istio ambient mode** and **ztunnel** (Cilium CNI, kubeadm bare metal or existing clusters, tests and benchmarks).

**Documentation:** [ztunnel-testbed/README.md](ztunnel-testbed/README.md)

## Default versions (ztunnel-testbed)

Same defaults as the testbed; change in `ztunnel-testbed/config/local.sh` or the files below.

| Component | Default | Config |
|-----------|---------|--------|
| Kubernetes (kubeadm) | 1.30.0 | `ztunnel-testbed/config/baremetal.sh` |
| Istio | 1.29.0 | `ztunnel-testbed/config/versions.sh` |
| Gateway API CRDs | v1.4.0 | `ztunnel-testbed/config/versions.sh` |
| Cilium | 1.16.0 | `ztunnel-testbed/config/cilium.sh` |

Quick start (from `ztunnel-testbed/`):

```bash
cd ztunnel-testbed
make setup          # existing cluster: Istio + apps
# or: make create-baremetal   # new kubeadm cluster on control-plane
```
