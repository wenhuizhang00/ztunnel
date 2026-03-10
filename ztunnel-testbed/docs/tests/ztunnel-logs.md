# Test: ztunnel-logs

**Script**: `tests/functionality/test-ztunnel-logs.sh`
**Category**: Infrastructure
**Prerequisites**: ztunnel running (make install)

## What it tests

ztunnel is not crash-looping and has no fatal errors.

## Why this matters

Crash-looping ztunnel means flapping mesh connectivity. Fatal errors indicate bugs or misconfig.

## What it checks

1. Container restarts <= 2
2. No FATAL/panic/segfault in last 100 log lines

## How to run

```bash
make test-func TEST=ztunnel-logs
```

## Expected output

```
PASS: ztunnel pods healthy (restarts <= 2, no FATAL/panic/segfault in logs)
```

## Troubleshooting

Check `kubectl logs -n istio-system -l app=ztunnel`, check pod describe for OOM.
