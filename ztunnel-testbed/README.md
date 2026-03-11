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

## Architecture: Pods and Networks

### Cluster layout (two-node example)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                                   │
│                                                                             │
│  ┌─ Control-plane node (<control-plane-ip>) ─────────────────────────────┐ │
│  │                                                                        │ │
│  │  System pods (kube-system):                                           │ │
│  │    • kube-apiserver          (API server, port 6443)                  │ │
│  │    • etcd                    (cluster state store)                    │ │
│  │    • kube-controller-manager (reconciliation loops)                   │ │
│  │    • kube-scheduler          (pod scheduling)                        │ │
│  │    • coredns × 2             (cluster DNS, 10.96.0.10)               │ │
│  │    • kube-proxy              (iptables rules for Services)           │ │
│  │                                                                        │ │
│  │  CNI pods (calico-system):                                            │ │
│  │    • calico-node             (BGP routing, network policy)           │ │
│  │    • calico-typha            (datastore proxy)                       │ │
│  │    • calico-kube-controllers (Calico reconciliation)                 │ │
│  │    • calico-apiserver        (Calico API)                            │ │
│  │                                                                        │ │
│  │  Istio pods (istio-system):                                           │ │
│  │    • istiod                  (control plane: xDS, certs, discovery)  │ │
│  │    • ztunnel                 (L4 proxy, mTLS, per-node DaemonSet)    │ │
│  │    • istio-cni-node          (traffic redirect: iptables/eBPF)       │ │
│  │                                                                        │ │
│  │  App pods (grimlock namespace, ambient mode):                         │ │
│  │    • http-echo × 2           (test HTTP server, port 8080)           │ │
│  │    • curl-client × 2         (test client with curl)                 │ │
│  │    • fortio-server           (perf test server, port 8080)           │ │
│  │    • fortio-client           (perf test load generator)              │ │
│  │    • fortio-server-cp  ←── pinned to this node (two-node test)      │ │
│  │                                                                        │ │
│  │  App pods (grimlock-baseline namespace, NO ambient):                  │ │
│  │    • http-echo × 2           (baseline, no ztunnel)                  │ │
│  │    • curl-client × 2         (baseline client)                       │ │
│  │    • fortio-server           (baseline perf server)                  │ │
│  │    • fortio-client           (baseline perf client)                  │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌─ Worker node (<worker-ip>) ────────────────────────────────────────────┐ │
│  │                                                                        │ │
│  │  CNI pods:                                                            │ │
│  │    • calico-node             (BGP routing on this node)              │ │
│  │                                                                        │ │
│  │  Istio pods:                                                          │ │
│  │    • ztunnel                 (L4 proxy for this node's pods)         │ │
│  │    • istio-cni-node          (traffic redirect for this node)        │ │
│  │                                                                        │ │
│  │  App pods (grimlock, ambient):                                        │ │
│  │    • fortio-client-wk  ←── pinned to this node (two-node test)      │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Network layers

There are three independent network layers in this setup:

```
Layer 3: ztunnel HBONE (encrypted)
  ┌──────────────────────────────────────────────────────────────────┐
  │  pod → istio-cni redirect → ztunnel → HBONE mTLS → ztunnel → pod │
  │  (transparent to applications, provides mTLS + L4 policy)       │
  └──────────────────────────────────────────────────────────────────┘

Layer 2: Calico pod network (flat routing, no VXLAN)
  ┌──────────────────────────────────────────────────────────────────┐
  │  Pod CIDR: 192.168.0.0/16                                       │
  │  Each node gets a /26 block (e.g., 192.168.247.64/26)          │
  │  Cross-node: BGP advertises pod routes between nodes            │
  │  No overlay (encapsulation: None) — direct L3 routing           │
  └──────────────────────────────────────────────────────────────────┘

Layer 1: Node network (physical/underlay)
  ┌──────────────────────────────────────────────────────────────────┐
  │  Node IPs: <control-plane-ip>, <worker-ip>                      │
  │  Service CIDR: 10.96.0.0/12 (kube-proxy iptables NAT)          │
  │  Physical network between nodes                                  │
  └──────────────────────────────────────────────────────────────────┘
```

### How a cross-node request flows (detailed)

When `fortio-client-wk` (on worker) sends a request to `fortio-server-cp` (on control-plane):

```
Step 1: Application sends request
  fortio-client-wk pod (192.168.x.y) → HTTP to fortio-server-cp:8080

Step 2: istio-cni-node redirects to ztunnel (on worker)
  • iptables TPROXY rule (Calico) or eBPF tc hook (Cilium)
  • Outbound TCP from ambient pod → ztunnel:15001
  • This is transparent — the app doesn't know about ztunnel

Step 3: ztunnel (worker) processes outbound
  • Looks up destination in xDS config (pushed by Istiod)
  • Finds: destination pod is on a different node
  • Selects SPIFFE certificate for the source workload identity
  • Opens HBONE tunnel to remote ztunnel

Step 4: HBONE tunnel over the network
  • TCP connection: worker:ephemeral → control-plane:15008
  • TLS 1.3 handshake (mTLS with SPIFFE X.509 certs)
  • HTTP/2 CONNECT request carries the original TCP stream
  • Payload is encrypted end-to-end

Step 5: ztunnel (control-plane) processes inbound
  • Receives on port 15008, terminates TLS
  • Verifies source SPIFFE identity
  • Checks L4 AuthorizationPolicy (if any)
  • Delivers decrypted TCP stream to the destination pod

Step 6: Pod receives the request
  • fortio-server-cp pod receives the original HTTP request
  • Responds normally; response takes the reverse path

Network path (Layer 2, Calico flat routing):
  worker eth0 → BGP-learned route → control-plane eth0
  No VXLAN encapsulation, no overlay headers
  Pod IPs are directly routable between nodes via BGP
```

### Namespace comparison

| Namespace | Ambient | Traffic path | Purpose |
|-----------|---------|-------------|---------|
| `grimlock` | Yes (`istio.io/dataplane-mode=ambient`) | pod → ztunnel → HBONE mTLS → ztunnel → pod | Mesh traffic with encryption |
| `grimlock-baseline` | No (no label) | pod → pod (direct, Calico routing only) | Baseline comparison, no mesh |
| `istio-system` | N/A | Host network for ztunnel, istiod | Istio control + data plane |
| `calico-system` | N/A | Host network for calico-node | CNI networking |
| `kube-system` | N/A | Host network | Kubernetes system components |

### Pod reference

| Pod | Namespace | Node | Purpose |
|-----|-----------|------|---------|
| **istiod** | istio-system | control-plane | Istio control plane: pushes config/certs to ztunnel |
| **ztunnel** | istio-system | every node (DaemonSet) | L4 mTLS proxy, HBONE tunnels |
| **istio-cni-node** | istio-system | every node (DaemonSet) | Configures iptables/eBPF to redirect ambient pod traffic to ztunnel |
| **calico-node** | calico-system | every node (DaemonSet) | BGP routing, network policy |
| **http-echo** | grimlock | any | Test HTTP server (returns "hello-from-pod") |
| **curl-client** | grimlock | any | Test client (curl available for kubectl exec) |
| **fortio-server** | grimlock | any | Performance test server (fortio server mode) |
| **fortio-client** | grimlock | any | Performance test load generator |
| **fortio-server-cp** | grimlock | control-plane (pinned) | Two-node test: server on control-plane |
| **fortio-client-wk** | grimlock | worker (pinned) | Two-node test: client on worker |

### How to verify each layer

#### 1. Verify nodes and pod placement

```bash
# All nodes Ready
kubectl get nodes -o wide

# All pods across all namespaces
kubectl get pods -A -o wide

# Pods in ambient namespace with node placement
kubectl get pods -n grimlock -o wide

# Two-node test pods pinned correctly
kubectl get pods -n grimlock -l test=two-node -o wide
```

#### 2. Verify Calico flat routing (no VXLAN)

```bash
# Confirm no vxlan.calico interface (should return nothing)
ip link show | grep vxlan

# Confirm Calico is using direct routing (BGP)
kubectl get ippool default-ipv4-ippool -o yaml | grep encapsulation
# Should show: encapsulation: None

# Check BGP peer status (Calico uses BGP for flat routing)
kubectl exec -n calico-system -l k8s-app=calico-node -- calico-node -birdcl show protocols 2>/dev/null || \
  kubectl exec -n calico-system -l k8s-app=calico-node -- birdcl show protocols 2>/dev/null || true

# Verify pod routes are directly routable between nodes
# On the control-plane, check route to worker's pod subnet:
ip route | grep 192.168

# On the worker, check route to control-plane's pod subnet:
ip route | grep 192.168
```

#### 3. Verify Istio ambient mode and ztunnel

```bash
# Istiod running
kubectl get deployment istiod -n istio-system

# ztunnel DaemonSet running on all nodes
kubectl get daemonset ztunnel -n istio-system

# istio-cni-node running on all nodes
kubectl get daemonset istio-cni-node -n istio-system

# grimlock namespace has ambient label
kubectl get namespace grimlock --show-labels | grep ambient

# grimlock-baseline does NOT have ambient label
kubectl get namespace grimlock-baseline --show-labels
```

#### 4. Verify ztunnel is intercepting traffic (iptables rules)

```bash
# Check iptables TPROXY rules set by istio-cni-node
# (run on the node where ambient pods are running)
sudo iptables -t mangle -L PREROUTING -n | grep TPROXY
sudo iptables -t mangle -L OUTPUT -n | grep TPROXY

# Or check the ztunnel listening ports
sudo ss -tlnp | grep -E '15001|15008'
# 15001 = ztunnel outbound listener
# 15008 = ztunnel HBONE inbound listener
```

#### 5. Verify SPIFFE certificates (mTLS)

```bash
# List all certificates ztunnel holds
./bin/istioctl ztunnel-config certificates

# Should show entries like:
#   spiffe://cluster.local/ns/grimlock/sa/default    Leaf  Available  true
#   spiffe://cluster.local/ns/grimlock/sa/default    Root  Available  true

# Verify a specific workload's mTLS status
./bin/istioctl ztunnel-config workloads | grep grimlock
# HBONE in the Protocol column = traffic goes through encrypted tunnel
```

#### 6. Verify HBONE tunnel is active (cross-node)

```bash
# Send a request and check ztunnel logs for HBONE activity
kubectl exec -n grimlock deploy/curl-client -- curl -s http://http-echo:80/

# Check ztunnel logs for connection entries
kubectl logs -n istio-system -l app=ztunnel --tail=20 | grep -E "inbound|outbound|CONNECT"

# Check ztunnel metrics for TCP connection counts
kubectl exec -n istio-system -l app=ztunnel -- \
  curl -s localhost:15020/metrics 2>/dev/null | grep istio_tcp_connections_opened_total
```

#### 7. Verify cross-node connectivity (two-node test)

```bash
# Deploy and verify two-node test
make setup-two-node
make verify-two-node

# Manual connectivity test: client on worker → server on control-plane
CLIENT=$(kubectl get pods -n grimlock -l app=fortio-client-wk -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n grimlock $CLIENT -c fortio -- \
  fortio curl http://fortio-server-cp.grimlock.svc.cluster.local:8080/

# Confirm pods are on different nodes
kubectl get pods -n grimlock -l test=two-node -o wide
```

#### 8. Verify ambient vs baseline (encryption proof)

```bash
# Run the mTLS verification test (checks certs, HBONE enrollment, proxy logs, metrics)
make test-func TEST=mtls-policy

# Compare: request through ambient (encrypted via ztunnel)
kubectl exec -n grimlock deploy/curl-client -- curl -s http://http-echo:80/

# Compare: request through baseline (direct, no encryption)
kubectl exec -n grimlock-baseline deploy/curl-client -- curl -s http://http-echo:80/

# Both return the same response, but:
# - ambient: traffic is encrypted (check ztunnel logs)
# - baseline: traffic is plaintext (no ztunnel logs)
kubectl logs -n istio-system -l app=ztunnel --tail=10 --since=5s | grep -c "inbound\|outbound"
# > 0 after ambient request, 0 after baseline request
```

#### Quick full verification (all at once)

```bash
# Run all 17 functionality tests (includes all checks above)
make test-func TEST=--all

# Or run the full interactive test suite
make test-func
```

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

#### Step 1: On the control-plane node

```bash
# Install prerequisites (kubeadm, kubelet, kubectl, containerd)
sudo ./scripts/install-baremetal-prereqs.sh

# Create cluster
make create-baremetal

# The output will print a join command like:
#   kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
# Copy this command — you'll need it for the worker node.
```

#### Step 2: On each worker node

```bash
# Clone or copy the repo to the worker node, then:
cd ztunnel/ztunnel-testbed

# Install prerequisites (same as control-plane — required on every node)
sudo ./scripts/install-baremetal-prereqs.sh

# Join the cluster using the command from Step 1:
sudo ./scripts/baremetal/install-and-join-worker.sh \
  --join "kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"

# If the worker was previously in another cluster (stale kubelet.conf/pki):
sudo ./scripts/baremetal/install-and-join-worker.sh --reset \
  --join "kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
```

#### Step 3: Verify on control-plane

```bash
kubectl get nodes -o wide
# Should show both nodes Ready
```

#### Step 4: Install Istio + deploy + test

```bash
# On the control-plane:
make setup

# Run tests (includes same-node AND cross-node ztunnel tests)
make test-func                              # interactive menu
make test-func TEST=ztunnel-cross-node      # cross-node HBONE tunnel test only
make test-func TEST=ztunnel-local           # same-node ztunnel test only
make test-perf                              # performance benchmarks
```

**Alternative: Automatic via SSH** (from control-plane, no manual steps on worker):
```bash
WORKER_NODES="<worker-ip>" make create-baremetal
```
Requires SSH key access from control-plane to worker (`ssh <user>@<worker-ip>`) and passwordless sudo on the worker.

For multiple workers: `WORKER_NODES="<ip1>,<ip2>" make create-baremetal` or repeat Step 2 on each worker.

### Two-Node Cross-Node Testing

After setting up a multi-node cluster, deploy dedicated cross-node test pods for benchmarking the ztunnel HBONE tunnel between two specific nodes.

#### How ztunnel ambient traffic routing works

When a pod is in an ambient namespace (`istio.io/dataplane-mode=ambient`), the Istio CNI plugin configures the node's network to redirect all traffic from that pod through the local ztunnel proxy. Here is the full packet path for a cross-node request:

```
┌─ Worker node ────────────────────────────────────────────────────────────┐
│                                                                           │
│  1. fortio-client-wk pod sends HTTP request to fortio-server-cp:8080     │
│     (destination = ClusterIP or Pod IP on the control-plane)             │
│                                                                           │
│  2. istio-cni + iptables/eBPF redirects the packet to ztunnel            │
│     ┌──────────────────────────────────────────────────────────┐         │
│     │ istio-cni-node (DaemonSet) configures:                   │         │
│     │  • iptables TPROXY rules (Calico/default CNI), OR       │         │
│     │  • eBPF tc programs (Cilium CNI)                        │         │
│     │ All outbound TCP from ambient pods → ztunnel:15001      │         │
│     │ All inbound TCP to ambient pods → ztunnel:15008         │         │
│     └──────────────────────────────────────────────────────────┘         │
│                                                                           │
│  3. ztunnel (worker) intercepts the outbound connection                  │
│     • Looks up the destination workload in its xDS config from Istiod   │
│     • Determines the destination is on a DIFFERENT node                  │
│     • Initiates an HBONE tunnel to the remote ztunnel                   │
│                                                                           │
│  4. HBONE tunnel establishment (mTLS):                                   │
│     • ztunnel (worker) opens a TCP connection to ztunnel (CP):15008     │
│     • TLS handshake using SPIFFE certificates:                          │
│       - Client cert: spiffe://cluster.local/ns/grimlock/sa/default      │
│       - Server cert: spiffe://cluster.local/ns/istio-system/sa/ztunnel  │
│     • Sends HTTP/2 CONNECT request with target pod identity             │
│     • Original L4 payload is tunneled inside the encrypted HBONE stream │
│                                                                           │
└───────────────── TCP over network (encrypted) ───────────────────────────┘
                              │
                              ▼
┌─ Control-plane node ─────────────────────────────────────────────────────┐
│                                                                           │
│  5. ztunnel (control-plane) receives the HBONE connection on :15008     │
│     • Terminates TLS, verifies client SPIFFE identity                   │
│     • Checks L4 AuthorizationPolicy (if any)                            │
│     • Extracts the original TCP stream from the HBONE tunnel            │
│                                                                           │
│  6. ztunnel delivers the packet to fortio-server-cp pod                 │
│     • Connects to the pod's real IP:port (via the pod network)          │
│     • No iptables redirect needed here — ztunnel connects directly      │
│                                                                           │
│  7. fortio-server-cp processes the HTTP request and responds            │
│     • Response follows the reverse path back through ztunnel            │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

#### ztunnel on each node

Every node in the cluster runs a ztunnel pod (DaemonSet in `istio-system`). All ztunnel instances are identical — there is no difference between ztunnel on the worker and ztunnel on the control-plane. Each ztunnel:

- **Receives xDS config from Istiod**: workload list, policies, certificates
- **Handles outbound**: intercepts traffic FROM local pods, encrypts with mTLS, tunnels via HBONE
- **Handles inbound**: receives HBONE tunnels FROM remote ztunnels, decrypts, delivers to local pods
- **Manages certificates**: holds SPIFFE identities for all local workloads, auto-rotated by Istiod

#### HBONE mTLS protocol

HBONE (HTTP-Based Overlay Network Encapsulation) is the tunneling protocol used by ztunnel:

1. **Transport**: TCP connection between ztunnel instances (port 15008)
2. **Encryption**: TLS 1.3 with SPIFFE X.509 certificates (mTLS — both sides present certs)
3. **Tunneling**: HTTP/2 CONNECT method carries the original TCP stream inside the encrypted channel
4. **Identity**: Each workload has a SPIFFE identity (e.g., `spiffe://cluster.local/ns/grimlock/sa/default`)
5. **Connection reuse**: Multiple L4 connections between pods on the same node pair share a single HBONE tunnel

#### Traffic interception: iptables vs eBPF

How traffic gets redirected from pods to ztunnel depends on the CNI:

| CNI | Interception method | How it works |
|-----|-------------------|--------------|
| **Calico** (default) | iptables TPROXY | `istio-cni-node` adds iptables rules in the pod's network namespace. Outbound TCP → TPROXY to ztunnel:15001. Inbound TCP → TPROXY to ztunnel:15008. |
| **Cilium** | eBPF tc programs | `istio-cni-node` attaches eBPF programs to the pod's veth interface. More efficient than iptables; no conntrack overhead. Requires `cni.exclusive=false` in Cilium config. |

The testbed scripts handle this automatically:

- `create-cluster-baremetal.sh` installs Calico (default) or Cilium (`CNI_PROVIDER=cilium`)
- `install-istio.sh` installs Istio ambient with `istio-cni-node` DaemonSet
- `istio-cni-node` detects the CNI and configures the appropriate interception rules
- No manual iptables or eBPF configuration is needed

#### Setup scripts explained

| Script | What it does |
|--------|-------------|
| `create-cluster-baremetal.sh` | Creates k8s cluster with kubeadm, installs Calico/Cilium CNI, configures containerd, sets up kubeconfig |
| `install-istio.sh` | Downloads istioctl, installs Gateway API CRDs, runs `istioctl install --set profile=ambient` which deploys Istiod + ztunnel DaemonSet + istio-cni-node DaemonSet |
| `deploy-sample-apps.sh` | Creates grimlock namespace with `istio.io/dataplane-mode=ambient` label (triggers ztunnel interception), deploys test pods |
| `setup-two-node-test.sh` | Pins fortio-server-cp to control-plane node and fortio-client-wk to worker node using `nodeName` scheduling |

#### Running the two-node benchmark

```bash
# 1. Deploy server on control-plane, client on worker
make setup-two-node

# 2. Verify pod placement and connectivity
make verify-two-node

# 3. Run cross-node throughput + latency benchmark
make bench-two-node

# 4. Custom parameters
DURATION=30s CONCURRENCY=64 make bench-two-node

# 5. Clean up when done
make clean-two-node
```

The two-node benchmark measures:
- **Throughput**: QPS/Kpps/Mbps by payload size (64-1500B) across nodes
- **Concurrency sweep**: Peak throughput at c=1,4,8,16,32,64,128
- **Latency**: Min/Avg/Max/P99 in microseconds per payload size and HTTP method
- **ztunnel resource usage**: CPU/memory before and after load

Node IPs are auto-detected from the cluster. Override in `config/local.sh` if needed:

```bash
CONTROL_PLANE_IP="<control-plane-ip>"
WORKER_IP="<worker-ip>"
```

| Target | Description |
|--------|-------------|
| `make setup-two-node` | Deploy fortio-server on control-plane, fortio-client on worker |
| `make verify-two-node` | Verify pod placement, connectivity, ztunnel enrollment |
| `make bench-two-node` | Run cross-node throughput + latency benchmark |
| `make clean-two-node` | Remove two-node test pods |

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
| `make create-baremetal-multi WORKER=<worker-ip>` | Create multi-node cluster |
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
WORKER_NODES="<worker-ip>"            # comma-separated worker IPs
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
    2) Latency test (average of P99 in microseconds)
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
| **Payload sizes** | Max QPS for 64-1500B POST | Min/Avg/Max + average of P99 in microseconds |
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

### Ztunnel timeout / "resources not ready after 5m0s" (Calico)

If `make install` fails with:

```
❗ detected Calico CNI with 'bpfConnectTimeLoadBalancing=TCP'; this must be set to 'bpfConnectTimeLoadBalancing=Disabled'
✘ Ztunnel encountered an error: failed to wait for resource: resources not ready after 5m0s
```

or ztunnel shows `0/2 ready`, Calico's eBPF connect-time load balancing interferes with Istio ambient. Fix:

```bash
# 1. Apply FelixConfiguration (disables connect-time load balancing)
kubectl apply -f manifests/cni/calico-felix-istio-ambient.yaml

# 2. Restart Calico so it picks up the new config
kubectl rollout restart daemonset/calico-node -n calico-system

# 3. Wait for Calico, then ztunnel should become ready
kubectl rollout status daemonset/calico-node -n calico-system --timeout=120s
kubectl rollout status daemonset/ztunnel -n istio-system --timeout=120s

# 4. Deploy sample apps
make deploy
```

For **new clusters**, `calico-custom-resources.yaml` already includes this FelixConfiguration.

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
- [Test Reference (each test explained)](docs/tests/README.md)
- [Directory Structure](docs/STRUCTURE.md)
