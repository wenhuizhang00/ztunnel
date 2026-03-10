# Test: istiod-ready

**Script**: `tests/functionality/test-istiod-ready.sh`
**Category**: Infrastructure
**Prerequisites**: Istio installed (make install)

## What it tests

Istiod control plane has at least 1 ready replica.

## Why this matters

Istiod pushes xDS config to ztunnel and manages certs. Without healthy istiod, ztunnel can't get config and new workloads won't get certs.

## What it checks

1. istiod deployment exists
2. >= 1 ready replica
3. Reports image version

## How to run

```bash
make test-func TEST=istiod-ready
```

## Expected output

```
PASS: istiod ready (1/1 replicas), image: ...
```

## Troubleshooting

Check `kubectl logs -n istio-system deploy/istiod`, check pod events.
