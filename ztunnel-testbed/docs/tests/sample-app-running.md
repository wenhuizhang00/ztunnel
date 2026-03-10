# Test: sample-app-running

**Script**: `tests/functionality/test-sample-app-running.sh`
**Category**: Application
**Prerequisites**: make deploy

## What it tests

http-echo and curl-client have ready pods.

## Why this matters

These are the sample workloads for connectivity tests. If not running, pod-to-pod and service tests fail.

## What it checks

1. http-echo >= 1 ready replica
2. curl-client >= 1 ready replica

## How to run

```bash
make test-func TEST=sample-app-running
```

## Expected output

```
PASS: http-echo and curl-client ready
```

## Troubleshooting

Check `kubectl get pods -n grimlock`, check image pull status.
