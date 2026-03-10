# Test: ztunnel-local

**Script**: `tests/functionality/test-ztunnel-local.sh`
**Category**: Multi-node (also works on single-node)
**Prerequisites**: make deploy

## What it tests

Same-node pod-to-pod communication through the local ztunnel. Verifies that even local traffic is intercepted for mTLS.

## Network layout

```
┌─ Single node (10.136.0.65) ──────────────────────────────────────────────┐
│                                                                           │
│  ┌─ curl-client pod ─────────┐          ┌─ http-echo pod ─────────────┐ │
│  │ IP: 192.168.93.197        │          │ IP: 192.168.93.194          │ │
│  │ eth0 (veth pair)          │          │ eth0 (veth pair)            │ │
│  └─────────┬─────────────────┘          └──────────────▲──────────────┘ │
│            │                                           │                 │
│            │ ① TCP: 192.168.93.197 →                   │                 │
│            │    192.168.93.194:8080                     │                 │
│            │                                           │                 │
│  ┌─────────▼───────────────────────────────────────────┤──────────────┐ │
│  │                     ztunnel pod                      │              │ │
│  │                     IP: 10.136.0.65 (host network)  │              │ │
│  │                                                      │              │ │
│  │   ② TPROXY intercepts outbound → :15001             │              │ │
│  │                                                      │              │ │
│  │   ③ Same-node delivery:                             │              │ │
│  │      • NO HBONE tunnel needed                       │              │ │
│  │      • mTLS applied locally (encrypt/decrypt)       │              │ │
│  │      • Loopback path through ztunnel                │              │ │
│  │                                                      │              │ │
│  │   ④ Inbound listener :15008 → deliver to pod ───────┘              │ │
│  │                                                                     │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  Key difference from cross-node:                                         │
│    • No HBONE tunnel (no TCP between ztunnel instances)                 │
│    • No network transit (stays on loopback/local)                       │
│    • Still encrypted with mTLS (SPIFFE certs)                           │
│    • Lower latency than cross-node (~100-200us vs ~300-500us)           │
│                                                                           │
│  Host interfaces:                                                        │
│    eno1: 10.136.0.65/24 (not used for same-node traffic)               │
│    calif73830f3e8a: → curl-client (192.168.93.197)                      │
│    cali4251e27b60f: → http-echo (192.168.93.194)                        │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### IP addresses at each hop

| Hop | Source IP | Dest IP | Notes |
|-----|-----------|---------|-------|
| ① App sends | 192.168.93.197 | 192.168.93.194:8080 | Original TCP |
| ② TPROXY | 192.168.93.197 | 192.168.93.194:8080 | Redirected to ztunnel:15001 |
| ③ ztunnel local | — | — | mTLS encrypt/decrypt (no network) |
| ④ Deliver | ztunnel | 192.168.93.194:8080 | Delivered to http-echo |

## Why this matters

Even same-node traffic is intercepted by ztunnel for mTLS and policy enforcement. The path is local (no HBONE tunnel, no network transit), so this tests the baseline ztunnel overhead without network latency.

## What it checks

1. Client and server pods are on the same node
2. HTTP request through local ztunnel succeeds
3. ztunnel proxy logs show interception entries
4. Falls back to regular pods on single-node clusters

## How to run

```bash
make test-func TEST=ztunnel-local
```

## Expected output

```
>>> Test: ztunnel local (same-node) traffic
    Tests pod-to-pod on the SAME node through local ztunnel.
      → client node: snc2-l54-5-s2, echo node: snc2-l54-5-s2 (single-node mode)
      → response: hello-from-pod
      → ztunnel proxy log entries (last 5s): 2 (>0 = traffic intercepted)
    PASS: Local ztunnel: same-node pod-to-pod OK
```

## Troubleshooting

- Check ztunnel logs for local traffic: `kubectl logs -n istio-system -l app=ztunnel | grep inbound`
- Check CNI redirect: `sudo iptables -t mangle -L | grep TPROXY`
- Check ambient label: `kubectl get ns grimlock --show-labels`
