# Test: two-node-setup

**Script**: `tests/functionality/test-two-node-setup.sh`
**Category**: Multi-node
**Prerequisites**: Multi-node cluster + make setup-two-node

## What it tests

Two-node test infrastructure: pod placement, 3 connectivity paths, mTLS enrollment.

## Why this matters

Verifies the dedicated cross-node fortio pods are correctly deployed for performance benchmarking.

## What it checks

1. fortio-server-cp on control-plane
2. fortio-client-wk on worker
3. Cross-node connectivity
4. Reverse connectivity
5. Same-node connectivity
6. ztunnel workload enrollment

*Skips if two-node pods not deployed.*

## How to run

```bash
make test-func TEST=two-node-setup
```

## Expected output

```
PASS: two-node setup verified (pod placement, 3 paths, mTLS enrollment)
```

## Troubleshooting

Run `make setup-two-node`, check node labels.
