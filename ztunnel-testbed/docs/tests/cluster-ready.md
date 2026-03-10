# Test: cluster-ready

**Script**: `tests/functionality/test-cluster-ready.sh`
**Category**: Infrastructure
**Prerequisites**: kubectl connected to cluster

## What it tests

All K8s nodes report Ready status.

## Why this matters

A NotReady node means kubelet can't schedule pods. Common causes: CNI not initialized, kubelet can't reach API server, or resource pressure (disk/memory).

## What it checks

1. Count nodes with Ready=True
2. Compare to total node count
3. Show each node's status

## How to run

```bash
make test-func TEST=cluster-ready
```

## Expected output

```
PASS: All 2/2 nodes Ready
```

## Troubleshooting

Check `kubectl describe node`, check kubelet logs, verify CNI, restart containerd.
