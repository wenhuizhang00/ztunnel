# ztunnel-testbed

Testbed for **Istio ambient mode** and **ztunnel** on Kubernetes: bare-metal kubeadm (Cilium, flat routing), functionality tests, and fortio-based benchmarks.

## Default versions

Override via `config/local.sh` or environment. Source of truth: `config/versions.sh`, `config/baremetal.sh`, `config/cilium.sh`.

| Component | Default |
|-----------|---------|
| Kubernetes (kubeadm) | 1.30.0 |
| Istio | 1.29.0 |
| Gateway API CRDs | v1.4.0 |
| Cilium | 1.16.0 |

**Stack:** Cilium CNI (`tunnel=disabled`, direct pod routing) → Istio ambient (`istiod`, `ztunnel`, `istio-cni-node`) → sample apps in `grimlock` (ambient) and `grimlock-baseline` (no mesh).

**Traffic path (ambient):** pod → istio-cni → ztunnel → HBONE mTLS → ztunnel → pod. Cross-node uses TCP :15008 between ztunnel instances. Details: [docs/tests/ztunnel-cross-node.md](docs/tests/ztunnel-cross-node.md).

---

## Prerequisites

- **Any cluster:** `kubectl`, `curl`
- **Bare metal:** `kubeadm`, `kubelet`, `containerd`, swap off, `overlay` + `br_netfilter` (`sudo modprobe overlay br_netfilter`)

```bash
sudo ./scripts/install-baremetal-prereqs.sh   # Ubuntu/Debian, on each node
```

---

## Quick start

### Existing cluster

```bash
kubectl cluster-info
make setup          # verify + Istio + sample apps
make test-func TEST=--all
```

### Bare metal — control-plane only (`make create-baremetal` runs **here** only)

```bash
sudo ./scripts/install-baremetal-prereqs.sh
make create-baremetal    # kubeadm init + Cilium + kubeconfig (context: grimlock-cell)
make setup
make test-func TEST=--all
```

### Bare metal — multi-node

1. **Control-plane:** prereqs + `make create-baremetal` (or `WORKER_NODES="<ip>" make create-baremetal` to join workers over SSH).
2. **Each worker:** prereqs + join (use command printed by kubeadm):

   ```bash
   sudo ./scripts/baremetal/install-and-join-worker.sh --join "kubeadm join ..."
   ```

3. **Control-plane:** `kubectl get nodes` → `make setup` → tests.

### kind / minikube / cloud

Create the cluster yourself, then `make setup` as above. Optional: `ISTIO_PLATFORM=gke|eks|k3d|minikube` for `istioctl` hints.

---

## Common Make targets

| Target | Purpose |
|--------|---------|
| `make setup` | `create` (connectivity) + `install` + `deploy` |
| `make create` | Check `kubectl` reaches cluster (does **not** create one) |
| `make create-baremetal` | New kubeadm cluster + Cilium |
| `make create-baremetal-multi WORKER=<ip>` | Same + auto-join workers via SSH |
| `make install` | Istio ambient + Gateway API CRDs |
| `make install-cilium` | Cilium only (existing cluster) |
| `make deploy` | Sample apps (+ cross-node manifests if ≥2 nodes) |
| `make test-func` | Interactive tests; `TEST=--all` for CI |
| `make test-list` | List test names |
| `make test-perf` / `make bench-quick` | Performance suite |
| `make setup-two-node` / `verify-two-node` / `bench-two-node` / `clean-two-node` | Pinned cross-node fortio |
| `make inspect` | ztunnel inspect script |
| `make clean` | Interactive uninstall (apps → istio → full → nuclear) |

Throughput/latency shortcuts: `bench-throughput`, `bench-latency`, `bench-throughput-cross`, `bench-latency-cross`, `bench-ambient`, `bench-baseline`. See [docs/TESTING.md](docs/TESTING.md) and Makefile for env vars (`MODE`, `TOPOLOGY`, `DURATION`, …).

---

## Configuration

Copy `config/local.sh.example` → `config/local.sh`. Typical overrides:

- `KUBE_CONTEXT` — default `grimlock-cell`
- `ISTIO_VERSION`, `GATEWAY_API_VERSION`
- `CILIUM_VERSION`, `CILIUM_NATIVE_ROUTING_CIDR` (match `POD_NETWORK_CIDR`)
- `WORKER_NODES`, `WORKER_SSH_USER` — multi-node automation
- `USE_LOCAL_IMAGES=1`, `IMAGE_REGISTRY` — local images (`make build-images`)

---

## Functionality tests

17 scripts under `tests/functionality/` (cluster, CNI, istiod, ztunnel, DNS, pod/service, ambient vs baseline, mTLS). Run:

```bash
make test-func TEST=--all
make test-func TEST=ztunnel-cross-node   # needs 2+ nodes + deploy
```

Per-test docs: [docs/tests/](docs/tests/README.md).

---

## Performance tests

Fortio client/server in ambient and baseline; single-node and cross-node topologies. Results under `.bench-results/`. Full options: [docs/TESTING.md](docs/TESTING.md).

---

## Useful checks

```bash
kubectl get nodes -o wide
kubectl get pods -n istio-system
kubectl get ns grimlock --show-labels
./bin/istioctl ztunnel-config workloads
kubectl exec -n grimlock deploy/curl-client -- curl -s http://http-echo:80/
```

---

## Troubleshooting (short)

| Issue | Hint |
|-------|------|
| `create-baremetal` / `apiserver.key` missing | Run init **only on control-plane**; `sudo kubeadm reset -f`; `sudo rm -rf /etc/kubernetes/pki` — see [docs/BAREMETAL.md](docs/BAREMETAL.md) |
| `localhost:8080` / no kubeconfig | `unset KUBECONFIG`; copy `/etc/kubernetes/admin.conf` to `~/.kube/config` |
| Node `NotReady` | `sudo systemctl restart containerd` |
| Corporate proxy | Set `HTTP_PROXY`/`HTTPS_PROXY`; script extends `NO_PROXY` + optional kubectl wrapper |
| ztunnel install timeout | Check `istiod`, image pulls, `kubectl rollout status ds/cilium -n kube-system` |
| Tests fail before deploy | Run `make install` and `make deploy` first |

Scripts log `[HH:MM:SS] [PHASE]` for long steps (kubeadm, Cilium, Istio, rollouts).

---

## Cleanup

```bash
make clean                 # menu
make clean CLEAN=apps      # grimlock namespaces only
make clean CLEAN=istio     # + Istio + Gateway API CRDs
make clean CLEAN=nuclear   # + kubeadm reset (destructive)
```

---

## Documentation

| Doc | Content |
|-----|---------|
| [docs/BAREMETAL.md](docs/BAREMETAL.md) | Prerequisites, proxy, worker join, PKI pitfalls |
| [docs/TESTING.md](docs/TESTING.md) | Functionality + performance testing |
| [docs/tests/README.md](docs/tests/README.md) | Each functionality test |
| [docs/STRUCTURE.md](docs/STRUCTURE.md) | Repo layout |

---

## Layout (abbreviated)

```
config/          versions, cluster, baremetal, cilium, kubeadm template, local.sh
manifests/       sample-apps, baseline, performance templates
scripts/         create-cluster-baremetal, install-istio, deploy, tests, cleanup, baremetal/
tests/           functionality/*.sh, performance/
images/          optional local http-echo, curl-client, fortio
```
