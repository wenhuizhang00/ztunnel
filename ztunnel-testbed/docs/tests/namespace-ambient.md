# Test: namespace-ambient

**Script**: `tests/functionality/test-namespace-ambient.sh`
**Category**: Application
**Prerequisites**: Sample apps deployed (make deploy)

## What it tests

grimlock namespace has istio.io/dataplane-mode=ambient label.

## Why this matters

This label is what tells Istio to capture traffic via ztunnel. Without it, pods are NOT in the mesh.

## What it checks

1. grimlock namespace exists
2. Label is set to "ambient"

## How to run

```bash
make test-func TEST=namespace-ambient
```

## Expected output

```
PASS: grimlock has istio.io/dataplane-mode=ambient
```

## Troubleshooting

Run `kubectl label namespace grimlock istio.io/dataplane-mode=ambient`
