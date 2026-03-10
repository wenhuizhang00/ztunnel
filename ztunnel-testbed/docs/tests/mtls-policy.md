# Test: mtls-policy

**Script**: `tests/functionality/test-mtls-policy.sh`
**Category**: Application
**Prerequisites**: Istio + sample apps deployed (make setup)

## What it tests

Proves that traffic between ambient pods is actually encrypted with mTLS. Performs 5 independent checks to verify encryption is happening.

## Network layout (encryption proof)

```
┌─ Node ─────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  ┌─ curl-client (grimlock, AMBIENT) ─┐                                     │
│  │ IP: 192.168.93.197                │                                     │
│  │ SPIFFE: spiffe://cluster.local/   │                                     │
│  │   ns/grimlock/sa/default          │                                     │
│  └──────────┬────────────────────────┘                                     │
│             │                                                               │
│  ① curl http://192.168.93.194:8080                                         │
│             │                                                               │
│  ┌──────────▼────────────────────────────────────────────────────────────┐ │
│  │  ztunnel                                                               │ │
│  │                                                                         │ │
│  │  Check 1: SPIFFE Certificates                                          │ │
│  │  ┌─────────────────────────────────────────────────────────────┐      │ │
│  │  │ istioctl ztunnel-config certificates shows:                  │      │ │
│  │  │  spiffe://cluster.local/ns/grimlock/sa/default  Leaf  ACTIVE│      │ │
│  │  │  spiffe://cluster.local/ns/grimlock/sa/default  Root  ACTIVE│      │ │
│  │  └─────────────────────────────────────────────────────────────┘      │ │
│  │                                                                         │ │
│  │  Check 2: HBONE Protocol                                              │ │
│  │  ┌─────────────────────────────────────────────────────────────┐      │ │
│  │  │ istioctl ztunnel-config workloads shows:                     │      │ │
│  │  │  grimlock  http-echo-xxx  192.168.93.194  node1  None  HBONE│      │ │
│  │  │  ^^^^^^ Protocol=HBONE means traffic is encrypted ^^^^^^^^^ │      │ │
│  │  └─────────────────────────────────────────────────────────────┘      │ │
│  │                                                                         │ │
│  │  Check 3: Proxy Interception (live request)                            │ │
│  │  ┌─────────────────────────────────────────────────────────────┐      │ │
│  │  │ After sending HTTP request:                                  │      │ │
│  │  │  ztunnel logs show: "inbound" / "outbound" / "src.xxx"     │      │ │
│  │  │  → Proves ztunnel intercepted and proxied the traffic       │      │ │
│  │  └─────────────────────────────────────────────────────────────┘      │ │
│  │                                                                         │ │
│  │  Check 4: Connection Metrics                                           │ │
│  │  ┌─────────────────────────────────────────────────────────────┐      │ │
│  │  │ curl localhost:15020/metrics shows:                          │      │ │
│  │  │  istio_tcp_connections_opened_total > 0                     │      │ │
│  │  │  istio_tcp_sent_bytes_total > 0                             │      │ │
│  │  │  → Proves ztunnel is in the data path                       │      │ │
│  │  └─────────────────────────────────────────────────────────────┘      │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌─ http-echo (grimlock, AMBIENT) ───┐                                     │
│  │ IP: 192.168.93.194                │                                     │
│  │ Returns: "hello-from-pod"         │                                     │
│  └───────────────────────────────────┘                                     │
│                                                                             │
│  Check 5: Namespace Label                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ kubectl get ns grimlock shows:                                       │  │
│  │  istio.io/dataplane-mode=ambient                                    │  │
│  │  → This label triggers ztunnel traffic capture                       │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### What "encrypted" means at each point

| Point | What happens | Evidence |
|-------|-------------|---------|
| App sends HTTP | Plaintext HTTP leaves the pod | — |
| ztunnel outbound | Encrypts with TLS 1.3 using SPIFFE cert | Check 1: cert exists |
| On the wire | mTLS encrypted payload (unreadable) | Check 2: HBONE protocol |
| ztunnel inbound | Decrypts, verifies identity, delivers | Check 3: proxy log entries |
| Metrics | Connection counters increase | Check 4: Prometheus metrics |

## Why this matters

This is the definitive proof that traffic is encrypted, not just routed. Without this test, you could have ambient mode "working" (pods communicate) but without actual mTLS encryption if certificates are misconfigured.

## What it checks

1. **SPIFFE certificates**: ztunnel holds active certs for grimlock workloads
2. **HBONE protocol**: workloads enrolled with HBONE (encrypted tunnel protocol)
3. **Live interception**: sending a request generates ztunnel proxy log entries
4. **Connection metrics**: istio_tcp_connections_opened_total > 0
5. **Namespace label**: grimlock has `istio.io/dataplane-mode=ambient`

## How to run

```bash
make test-func TEST=mtls-policy
```

## Expected output

```
>>> Test: mTLS encryption verification
    Proves traffic is encrypted: SPIFFE certs, HBONE protocol, ztunnel proxy logs, metrics.
      → Check 1: SPIFFE certificates for grimlock workloads
      → SPIFFE certs for grimlock: 2
      →   spiffe://cluster.local/ns/grimlock/sa/default  Leaf  Available  true
      → Check 2: Workloads enrolled in mesh with HBONE protocol
      → grimlock HBONE workloads: 4
      → Check 3: Live request through ztunnel (proof of interception)
      → request to 192.168.93.194: hello-from-pod
      → ztunnel proxy entries in last 10s: 2
      → Check 4: ztunnel connection metrics
      → TCP connections opened: 12
      → Check 5: Namespace grimlock ambient enrollment
      → grimlock dataplane-mode: ambient
    PASS: mTLS verified: SPIFFE certs active, HBONE protocol, ztunnel intercepting traffic
```

## Troubleshooting

- Check certificates: `istioctl ztunnel-config certificates`
- Check workloads: `istioctl ztunnel-config workloads | grep grimlock`
- Check ztunnel logs: `kubectl logs -n istio-system -l app=ztunnel --tail=20`
- Check istiod: `kubectl logs -n istio-system deploy/istiod --tail=20`
- Check ambient label: `kubectl get ns grimlock --show-labels`
