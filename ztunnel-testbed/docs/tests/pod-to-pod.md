# Test: pod-to-pod

**Script**: `tests/functionality/test-pod-to-pod.sh`
**Category**: Application
**Prerequisites**: make deploy

## What it tests

HTTP request from curl-client to http-echo pod IP directly through ztunnel. Tests the full L4 mTLS data path.

## Network layout

```
┌─ Node: snc2-l54-5-s2 (10.136.0.65) ─────────────────────────────────────┐
│                                                                           │
│  ┌─ curl-client pod ──────────┐     ┌─ http-echo pod ─────────────────┐ │
│  │ IP: 192.168.93.197         │     │ IP: 192.168.93.194              │ │
│  │ eth0 (veth → cali* on host)│     │ eth0 (veth → cali* on host)    │ │
│  │                            │     │ Listens: :8080                  │ │
│  │ curl http://192.168.93.194 │     │ Returns: "hello-from-pod"      │ │
│  │           :8080/           │     │                                 │ │
│  └────────────┬───────────────┘     └────────────────▲────────────────┘ │
│               │                                      │                   │
│               │ ① App sends TCP to 192.168.93.194:8080                  │
│               │                                      │                   │
│  ┌────────────▼──────────────────────────────────────┤───────────────┐  │
│  │                    ztunnel pod (host network)      │               │  │
│  │                    IP: 10.136.0.65                 │               │  │
│  │                                                    │               │  │
│  │  ② istio-cni iptables TPROXY intercepts           │               │  │
│  │     outbound TCP → ztunnel:15001                  │               │  │
│  │                                                    │               │  │
│  │  ③ ztunnel looks up destination in xDS config     │               │  │
│  │     → same node → local delivery                 │               │  │
│  │     → mTLS encrypt (even for same-node)           │               │  │
│  │                                                    │               │  │
│  │  ④ ztunnel delivers to http-echo pod ─────────────┘               │  │
│  │     via ztunnel:15008 inbound listener                            │  │
│  │                                                                    │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  Host interfaces:                                                        │
│    eno1: 10.136.0.65/24 (node IP, physical)                             │
│    calif73830f3e8a: → curl-client pod (192.168.93.197)                  │
│    cali4251e27b60f: → http-echo pod (192.168.93.194)                    │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### IP addresses at each hop

| Hop | Source IP | Dest IP | Interface | Notes |
|-----|-----------|---------|-----------|-------|
| ① App sends | 192.168.93.197 | 192.168.93.194:8080 | curl-client eth0 | Original packet |
| ② TPROXY intercept | 192.168.93.197 | 192.168.93.194:8080 | host cali* | iptables redirects to ztunnel:15001 |
| ③ ztunnel outbound | 192.168.93.197 | 192.168.93.194:8080 | ztunnel internal | Encrypted with mTLS (same-node: loopback) |
| ④ ztunnel inbound | ztunnel | 192.168.93.194:8080 | ztunnel → pod | Decrypted, delivered to http-echo |

## Why this matters

Tests the full L4 mTLS data path: curl-client → ztunnel (source) → mTLS → ztunnel (dest) → http-echo. If this fails but pod-to-service works, the issue is in direct pod IP routing through ztunnel.

## What it checks

1. curl-client pod exists in grimlock namespace
2. http-echo pod has a valid pod IP
3. HTTP request to pod_ip:8080 returns expected response containing "hello"
4. Skips if curl-client not deployed

## How to run

```bash
make test-func TEST=pod-to-pod
```

## Expected output

```
>>> Test: Pod-to-Pod direct (curl -> http-echo pod IP)
    Sends HTTP request to pod IP directly through ztunnel. Tests the L4 mTLS data path.
      → client=curl-client-xxx, target=192.168.93.194:8080
      → response: hello-from-pod
    PASS: Pod-to-pod direct: curl -> 192.168.93.194:8080 OK (256ms)
```

## Troubleshooting

- Check ztunnel logs: `kubectl logs -n istio-system -l app=ztunnel --tail=20`
- Check pod IPs: `kubectl get pods -n grimlock -o wide`
- Check ambient label: `kubectl get ns grimlock --show-labels`
- Check iptables redirect: `sudo iptables -t mangle -L | grep TPROXY`
