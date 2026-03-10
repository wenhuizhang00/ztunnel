# Test: bench-two-node

**Script**: `tests/performance/bench-two-node.sh`
**Category**: Performance
**Prerequisites**: make setup-two-node

## What it tests

Cross-node throughput and latency benchmarks through the ztunnel HBONE tunnel. Compares 3 paths to isolate the tunnel overhead.

## Network layout (3 test paths)

```
┌─ Worker node (10.136.11.5) ──────────┐    ┌─ Control-plane (10.136.0.65) ──┐
│                                       │    │                                 │
│  fortio-client-wk (192.168.42.142)   │    │  fortio-server-cp (192.168.93.  │
│  fortio-server-wk (192.168.42.143)   │    │                   202)          │
│  fortio-client-cp  ─── (on CP) ──────│────│──(192.168.93.203)               │
│                                       │    │                                 │
│  ztunnel (:15001 out, :15008 in)     │    │  ztunnel (:15001 out, :15008 in)│
└───────────────────────────────────────┘    └─────────────────────────────────┘


Path 1: CROSS-NODE (worker → control-plane, HBONE tunnel)
═════════════════════════════════════════════════════════════════
  fortio-client-wk          ztunnel         ztunnel          fortio-server-cp
  192.168.42.142    →    (worker)     →   (CP)        →    192.168.93.202
       │                     │                │                    │
       │  ① TCP to           │  ③ HBONE      │  ⑤ decrypt        │
       │  192.168.93.202     │  tunnel via    │  deliver to pod   │
       │  :8080              │  10.136.0.65   │                    │
       └─ ② TPROXY ─────────┘  :15008        └────────────────────┘
          to ztunnel:15001      (TLS 1.3)


Path 2: REVERSE (control-plane → worker, HBONE tunnel)
═════════════════════════════════════════════════════════════════
  fortio-client-cp          ztunnel         ztunnel          fortio-server-wk
  192.168.93.203    →    (CP)        →   (worker)     →    192.168.42.143
       │                     │                │                    │
       │  Same path but      │  HBONE to      │                   │
       │  reversed direction  │  10.136.11.5   │                   │
       │                     │  :15008        │                    │
       └─────────────────────┘                └────────────────────┘


Path 3: SAME-NODE (worker → worker, local ztunnel, no HBONE)
═════════════════════════════════════════════════════════════════
  fortio-client-wk          ztunnel                     fortio-server-wk
  192.168.42.142    →    (worker, local)          →    192.168.42.143
       │                     │                              │
       │  ① TCP to           │  ② local mTLS               │
       │  192.168.42.143     │  no HBONE needed             │
       │  :8080              │  (same node)                 │
       └─ TPROXY ────────────┘──────────────────────────────┘
```

### Comparing paths shows overhead

| Comparison | What it reveals |
|------------|----------------|
| Path 1 vs Path 3 | HBONE tunnel overhead (cross-node encryption + network transit) |
| Path 1 vs Path 2 | Directional asymmetry (should be similar) |
| Path 3 alone | Local ztunnel overhead (mTLS without network transit) |

### IP summary

| Pod | Node | IP | Role |
|-----|------|-----|------|
| fortio-client-wk | worker (10.136.11.5) | 192.168.42.142 | Load generator |
| fortio-server-cp | CP (10.136.0.65) | 192.168.93.202 | Cross-node target |
| fortio-server-wk | worker (10.136.11.5) | 192.168.42.143 | Same-node baseline |
| fortio-client-cp | CP (10.136.0.65) | 192.168.93.203 | Reverse direction client |

### Network path detail (cross-node)

```
fortio-client-wk (192.168.42.142)
    │ TCP SYN → 192.168.93.202:8080
    ▼
iptables TPROXY → ztunnel:15001 (worker)
    │ mTLS encrypt (SPIFFE cert)
    │ HTTP/2 CONNECT
    ▼
TCP: 10.136.11.5 → 10.136.0.65:15008 (encrypted, over eno1)
    │ Calico BGP route: 192.168.93.192/26 via 10.136.0.65
    ▼
ztunnel:15008 (CP) receives HBONE
    │ TLS terminate, verify SPIFFE identity
    │ Decrypt, extract original TCP
    ▼
fortio-server-cp (192.168.93.202:8080) — HTTP response
    │ Reverse path back through HBONE
    ▼
fortio-client-wk receives response
```

## Why this matters

Comparing cross-node vs same-node directly shows the HBONE tunnel overhead (typically +50-200us latency, -10-20% throughput). Comparing forward vs reverse shows if there's asymmetry.

## What it checks

- **Throughput**: QPS/Kpps/Mbps per payload size (64-1500B) for all 3 paths
- **Concurrency sweep**: Peak QPS at c=1,4,8,16,32,64,128 (cross-node)
- **Latency**: Min/Avg/Max/P99 per payload size + HTTP methods for all 3 paths
- **ztunnel resources**: CPU/memory before and after load

## How to run

```bash
# Full benchmark
make bench-two-node

# Quick (5s, skip concurrency sweep)
DURATION=5s SKIP_SWEEP=1 make bench-two-node

# Custom
DURATION=30s CONCURRENCY=64 make bench-two-node
```

## Expected output

```
========================================================================
  TWO-NODE CROSS-NODE BENCHMARK
  Path 1: snc2-l72-5-s1 → snc2-l54-5-s2 (cross-node, HBONE tunnel)
  Path 2: snc2-l54-5-s2 → snc2-l72-5-s1 (reverse, HBONE tunnel)
  Path 3: snc2-l72-5-s1 → snc2-l72-5-s1 (same-node, local ztunnel)
========================================================================

  --- cross-node (worker→CP) ---
  64B POST                      8234.5     8.2      4.22  100.0 %
  1500B POST                    5678.9     5.7     68.15  100.0 %

  --- same-node (worker→worker) ---
  64B POST                     13814.6    13.8      7.07  100.0 %
  1500B POST                    9234.5     9.2    110.81  100.0 %
```

## Troubleshooting

- Run `make setup-two-node` if pods not found
- Check placement: `make verify-two-node`
- Check inter-node connectivity: `ping <other-node-ip>`
- Check Calico routes: `ip route | grep 192.168`
- Check ztunnel: `kubectl logs -n istio-system -l app=ztunnel | grep HBONE`
