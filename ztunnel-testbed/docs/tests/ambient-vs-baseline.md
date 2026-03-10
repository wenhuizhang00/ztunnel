# Test: ambient-vs-baseline

**Script**: `tests/functionality/test-ambient-vs-baseline.sh`
**Category**: Application
**Prerequisites**: make deploy

## What it tests

grimlock has ambient, grimlock-baseline does NOT.

## Why this matters

Testbed runs identical apps in two namespaces. This test confirms the mesh is selectively applied so perf comparisons are valid.

## What it checks

1. grimlock has ambient label
2. grimlock-baseline does NOT
3. Both have running pods

*Skips if apps not deployed in both namespaces.*

## How to run

```bash
make test-func TEST=ambient-vs-baseline
```

## Expected output

```
PASS: grimlock=ambient, grimlock-baseline=no mesh, both have running pods
```

## Troubleshooting

Check namespace labels, redeploy apps.
