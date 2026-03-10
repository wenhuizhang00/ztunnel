# Test Documentation

Detailed documentation for each test in the ztunnel-testbed.

## Functionality Tests

### Infrastructure Tests (no sample apps needed)

| Test | Doc | Description |
|------|-----|-------------|
| cluster-ready | [cluster-ready.md](cluster-ready.md) | Checks all K8s nodes are Ready |
| cni-ready | [cni-ready.md](cni-ready.md) | Checks istio-cni-node DaemonSet is rolled out |
| gateway-api | [gateway-api.md](gateway-api.md) | Checks Gateway API CRDs are installed |
| istiod-ready | [istiod-ready.md](istiod-ready.md) | Checks Istiod control plane is running |
| ztunnel-ready | [ztunnel-ready.md](ztunnel-ready.md) | Checks ztunnel DaemonSet is ready on all nodes |
| ztunnel-certs | [ztunnel-certs.md](ztunnel-certs.md) | Checks ztunnel has SPIFFE mTLS certificates |
| ztunnel-logs | [ztunnel-logs.md](ztunnel-logs.md) | Checks ztunnel is not crash-looping |

### Application Tests (need `make deploy`)

| Test | Doc | Description |
|------|-----|-------------|
| namespace-ambient | [namespace-ambient.md](namespace-ambient.md) | Checks grimlock namespace has ambient label |
| ambient-vs-baseline | [ambient-vs-baseline.md](ambient-vs-baseline.md) | Validates selective mesh enrollment |
| sample-app-running | [sample-app-running.md](sample-app-running.md) | Checks http-echo and curl-client are ready |
| dns-resolution | [dns-resolution.md](dns-resolution.md) | Checks CoreDNS resolves service names inside pods |
| pod-to-pod | [pod-to-pod.md](pod-to-pod.md) | Tests direct pod IP request through ztunnel |
| pod-to-service | [pod-to-service.md](pod-to-service.md) | Tests Service→Pod request through ztunnel |
| ztunnel-workloads | [ztunnel-workloads.md](ztunnel-workloads.md) | Checks ztunnel sees workloads via istioctl |
| mtls-policy | [mtls-policy.md](mtls-policy.md) | Proves traffic is encrypted with mTLS |

### Multi-node Tests (need 2+ nodes)

| Test | Doc | Description |
|------|-----|-------------|
| ztunnel-local | [ztunnel-local.md](ztunnel-local.md) | Same-node pod-to-pod through local ztunnel |
| ztunnel-cross-node | [ztunnel-cross-node.md](ztunnel-cross-node.md) | Cross-node pod-to-pod through HBONE tunnel |
| two-node-setup | [two-node-setup.md](two-node-setup.md) | Verifies two-node test infrastructure |

## Performance Tests

| Test | Doc | Description |
|------|-----|-------------|
| bench-throughput | [bench-throughput.md](bench-throughput.md) | QPS/Kpps/Mbps by payload size |
| bench-latency | [bench-latency.md](bench-latency.md) | Min/Avg/Max/P99 latency in microseconds |
| bench-two-node | [bench-two-node.md](bench-two-node.md) | Cross-node vs same-node comparison |
