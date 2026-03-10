# Test: gateway-api

**Script**: `tests/functionality/test-gateway-api.sh`
**Category**: Infrastructure
**Prerequisites**: Gateway API CRDs installed (part of make install)

## What it tests

Gateway API CRDs (Gateway, HTTPRoute) exist.

## Why this matters

Istio ambient uses Gateway API for traffic routing. Without CRDs, you can't define routes and istioctl may fail.

## What it checks

1. gateways.gateway.networking.k8s.io CRD exists
2. httproutes.gateway.networking.k8s.io CRD exists

## How to run

```bash
make test-func TEST=gateway-api
```

## Expected output

```
PASS: Gateway API CRDs (Gateway, HTTPRoute) exist
```

## Troubleshooting

Re-run `make install`, or manually apply Gateway API CRDs.
