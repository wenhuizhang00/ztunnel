# Test: ztunnel-certs

**Script**: `tests/functionality/test-ztunnel-certs.sh`
**Category**: Infrastructure
**Prerequisites**: Istio installed, ztunnel running

## What it tests

ztunnel has active SPIFFE mTLS certificates.

## Why this matters

Each workload gets a SPIFFE cert (e.g. spiffe://cluster.local/ns/grimlock/sa/default). Without certs, mTLS fails and traffic is dropped.

## What it checks

1. istioctl ztunnel-config certificates returns output
2. Contains ACTIVE/VALID/spiffe entries
3. Reports cert count

*Skips if istioctl not found.*

## How to run

```bash
make test-func TEST=ztunnel-certs
```

## Expected output

```
PASS: ztunnel has active certificates (N certs, ACTIVE/VALID/spiffe entries found)
```

## Troubleshooting

Check istiod logs, check `istioctl ztunnel-config certificates` manually.
