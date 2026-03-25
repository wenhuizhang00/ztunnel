# Test: ztunnel-ready

**Script**: `tests/functionality/test-ztunnel-ready.sh`
**Category**: Infrastructure
**Prerequisites**: Istio installed (make install)

## What it tests

ztunnel DaemonSet has all pods running on every node.

## Why this matters

ztunnel is the per-node L4 proxy for ambient mode. If not ready on a node, pods on that node have no mesh connectivity.

## What it checks

1. ztunnel DaemonSet exists
2. numberReady == desired
3. Reports image version

## How to run

```bash
make test-func TEST=ztunnel-ready
```

## Expected output

```
PASS: ztunnel fully rolled out (3/3 ready), image: ...
```

## Troubleshooting

Check `kubectl get ds ztunnel -n istio-system`, check pod logs.

If ztunnel shows `0/N ready`, check istiod, image pulls, and Cilium: `kubectl rollout status ds/cilium -n kube-system`. See README troubleshooting for ztunnel install timeouts.
