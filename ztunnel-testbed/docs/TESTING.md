# Functionality Testing Guide

## Overview

The ztunnel-testbed includes 15 functionality tests that verify the health of the Kubernetes cluster, Istio ambient mode installation, ztunnel proxy, and end-to-end pod connectivity.

Tests are organized in `tests/functionality/` and run via `scripts/run-functionality-tests.sh`.

## Running Tests

### Interactive mode (default)

```bash
make test-func
```

Shows a numbered menu where you can select individual tests or run all:

```
Functionality Tests
─────────────────────────────────────────

   0) Run ALL tests
   1) ambient-vs-baseline
   2) cluster-ready
   3) cni-ready
   ...

Select test(s) [0=all, or numbers separated by spaces]: 2 5 7
```

### Run all tests (non-interactive, CI-friendly)

```bash
make test-func TEST=--all
```

### Run a single test by name

```bash
make test-func TEST=cluster-ready
make test-func TEST=pod-to-pod
make test-func TEST=ztunnel-certs
```

### Run tests matching a pattern

```bash
make test-func TEST=ztunnel    # runs ztunnel-ready, ztunnel-certs, ztunnel-logs, ztunnel-workloads
make test-func TEST=pod        # runs pod-to-pod, pod-to-service
```

### List available tests

```bash
make test-list
```

### Run a test script directly

```bash
./tests/functionality/test-cluster-ready.sh
```

## Test Output

Each test produces structured output with:

- **PASS** (green): Test assertion succeeded
- **FAIL** (red): Test assertion failed (script exits non-zero)
- **SKIP** (yellow): Precondition not met (e.g. sample apps not deployed)
- **detail** (dimmed): Diagnostic info (pod names, IPs, counts)
- **Timing**: Milliseconds per test for performance tracking

Example output:

```
>>> Test: ztunnel DaemonSet ready
      → ztunnel pods: 1/1, image: docker.io/istio/ztunnel:1.29.0-distroless
    PASS: ztunnel DaemonSet ready (1/1 pods) (45ms)
```

## Test Categories

### Infrastructure tests (no sample apps needed)

These tests verify the cluster and Istio control plane. Run them right after `make install`:

| Test | What it verifies |
|------|-----------------|
| **cluster-ready** | All Kubernetes nodes report Ready. Catches CNI issues, kubelet problems, resource pressure. |
| **cni-ready** | istio-cni-node DaemonSet is fully rolled out. Without Istio CNI, ambient traffic capture doesn't work. |
| **gateway-api** | Gateway API CRDs (Gateway, HTTPRoute) are installed. Required for Istio traffic routing. |
| **istiod-ready** | Istiod control plane has >= 1 ready replica. Reports image version. |
| **ztunnel-ready** | ztunnel DaemonSet has all pods ready. Reports pod count and image version. |
| **ztunnel-certs** | ztunnel has active mTLS certificates (SPIFFE identities). Uses `istioctl ztunnel-config certificates`. |
| **ztunnel-logs** | ztunnel container has <= 2 restarts and no FATAL/panic in recent logs. |

### Application tests (need `make deploy`)

These tests require sample apps to be deployed:

| Test | What it verifies |
|------|-----------------|
| **namespace-ambient** | `grimlock` namespace has `istio.io/dataplane-mode=ambient` label. |
| **ambient-vs-baseline** | `grimlock` has ambient, `grimlock-baseline` does NOT. Both have running pods. |
| **sample-app-running** | http-echo and curl-client deployments have ready pods. |
| **dns-resolution** | CoreDNS resolves `kubernetes.default` and `http-echo.<ns>` from inside a pod. |
| **pod-to-pod** | curl-client → http-echo pod IP (direct, through ztunnel HBONE tunnel). |
| **pod-to-service** | curl-client → http-echo ClusterIP Service (DNS + kube-proxy + ztunnel). |
| **ztunnel-workloads** | `istioctl ztunnel-config workloads` shows grimlock workloads. Confirms ztunnel "sees" your pods. |
| **mtls-policy** | Placeholder for PeerAuthentication / AuthorizationPolicy checks. Extend as needed. |

## Test Architecture

### lib.sh

`tests/lib.sh` provides the test helper functions:

```bash
test_start "Test name"     # Print header, start timer
pass "message"             # Green PASS + elapsed time
fail "message"             # Red FAIL + elapsed time, returns exit code 1
skip "reason"              # Yellow SKIP (test exits 0, not counted as fail)
detail "key=value"         # Dimmed detail line for diagnostics
```

### Test structure

Each test file follows this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Descriptive test name"

# ... kubectl queries, assertions ...
detail "some diagnostic info"

[[ "$condition" == "expected" ]] || fail "What went wrong"
pass "What succeeded"
```

### Exit codes

- **0**: All assertions passed (PASS)
- **1**: At least one assertion failed (FAIL)
- **0 with SKIP**: Test skipped (precondition not met, not a failure)

The test runner (`run-functionality-tests.sh`) counts pass/fail from each script's exit code.

## Extending Tests

### Add a new test

1. Create `tests/functionality/test-<name>.sh`
2. Source `lib.sh` and use `test_start`, `pass`, `fail`, `skip`, `detail`
3. Make it executable: `chmod +x tests/functionality/test-<name>.sh`
4. It will automatically appear in the test menu and `make test-func TEST=--all`

### Extend the mTLS/policy test

Edit `tests/functionality/test-mtls-policy.sh` and uncomment or add assertions:

```bash
# Check PeerAuthentication exists with STRICT mode
pa=$(kubectl get peerauthentication -n grimlock -o jsonpath='{.items[0].spec.mtls.mode}' 2>/dev/null)
[[ "$pa" == "STRICT" ]] || fail "PeerAuthentication not STRICT"

# Check AuthorizationPolicy
ap_count=$(kubectl get authorizationpolicy -n grimlock --no-headers 2>/dev/null | wc -l)
[[ "$ap_count" -gt 0 ]] || fail "No AuthorizationPolicy found"
```

## Troubleshooting

### Test shows SKIP

The test's precondition is not met. Common causes:
- Sample apps not deployed → run `make deploy`
- istioctl not found → run `make install`

### DNS test fails

Check CoreDNS is running: `kubectl get pods -n kube-system -l k8s-app=kube-dns`

### Pod-to-pod test fails with CURL_FAILED

1. Check pods are Running: `kubectl get pods -n grimlock`
2. Check ztunnel logs: `kubectl logs -n istio-system -l app=ztunnel --tail=20`
3. Check ambient label: `kubectl get ns grimlock --show-labels`

### ztunnel-certs shows 0 certificates

Istiod may not be pushing config. Check:
```bash
kubectl logs -n istio-system -l app=istiod --tail=20
./scripts/ztunnel-inspect.sh certificates
```
