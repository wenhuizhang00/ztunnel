# Test: cni-ready

**Script**: `tests/functionality/test-cni-ready.sh`
**Category**: Infrastructure
**Prerequisites**: Istio installed (make install)

## What it tests

istio-cni-node DaemonSet is fully rolled out on all nodes.

## Why this matters

Without Istio CNI, ambient traffic capture doesn't work. Pods won't have traffic redirected through ztunnel.

## What it checks

1. istio-cni-node DaemonSet exists
2. numberReady == desiredNumberScheduled

*Skips if istio-cni-node not found.*

## How to run

```bash
make test-func TEST=cni-ready
```

## Expected output

```
PASS: istio-cni-node fully rolled out (3/3 ready)
```

## Troubleshooting

Check `kubectl get ds istio-cni-node -n istio-system`, check pod logs.
