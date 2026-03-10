# Test: ztunnel-workloads

**Script**: `tests/functionality/test-ztunnel-workloads.sh`
**Category**: Application
**Prerequisites**: Istio + sample apps deployed

## What it tests

istioctl ztunnel-config workloads shows grimlock workloads.

## Why this matters

ztunnel maintains a table of all workloads it proxies. If a workload doesn't appear, the namespace may lack the ambient label or istiod isn't pushing config.

## What it checks

1. istioctl ztunnel-config workloads returns output
2. Contains grimlock/http-echo or HBONE entries

*Skips if istioctl not found.*

## How to run

```bash
make test-func TEST=ztunnel-workloads
```

## Expected output

```
PASS: ztunnel workloads include grimlock (http-echo, HBONE entries)
```

## Troubleshooting

Check ambient label, check istiod logs.
