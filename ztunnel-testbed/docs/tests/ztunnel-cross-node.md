# Test: ztunnel-cross-node

**Script**: `tests/functionality/test-ztunnel-cross-node.sh`
**Category**: Multi-node
**Prerequisites**: Multi-node deploy (make deploy with 2+ nodes)

## What it tests

Cross-node pod-to-pod communication through the ztunnel HBONE mTLS tunnel. Tests both directions: node1→node2 and node2→node1.

## Network layout

```
┌─ Control-plane node (10.136.0.65) ───────────────────────────────────────┐
│                                                                           │
│  ┌─ curl-client-node1 ───────┐     ┌─ http-echo-node1 ───────────────┐ │
│  │ IP: 192.168.93.200        │     │ IP: 192.168.93.201              │ │
│  │ eth0 → cali* on host      │     │ eth0 → cali* on host            │ │
│  │ Sends cross-node request  │     │ Returns: "hello-from-node1"     │ │
│  └────────────┬───────────────┘     └────────────────▲────────────────┘ │
│               │                                      │                   │
│  ┌────────────▼──────────────────────────────────────┤───────────────┐  │
│  │         ztunnel (10.136.0.65, host network)       │               │  │
│  │                                                    │               │  │
│  │  OUTBOUND (:15001):                               │               │  │
│  │  ② Intercepts curl-client-node1 TCP               │               │  │
│  │  ③ Encrypts with mTLS (SPIFFE cert)               │               │  │
│  │  ④ Opens HBONE tunnel to remote ztunnel:15008     │               │  │
│  │                                                    │               │  │
│  │  INBOUND (:15008):                     ⑨ delivers │               │  │
│  │  Receives HBONE from worker ztunnel ───────────────┘               │  │
│  │  Decrypts, delivers to http-echo-node1                            │  │
│  └────────────┬───────────────────────────────────────────────────────┘  │
│               │                                                           │
│  Host:  eno1: 10.136.0.65/24                                            │
│         Route: 192.168.42.128/26 via 10.136.11.5 proto bird            │
└───────────────┼──────────────────────────────────────────────────────────┘
                │
                │ ⑤ HBONE tunnel: TCP 10.136.0.65 → 10.136.11.5:15008
                │    (TLS 1.3, mTLS, HTTP/2 CONNECT)
                │    Payload: encrypted original TCP stream
                │
                │ ⑧ HBONE reverse: TCP 10.136.11.5 → 10.136.0.65:15008
                │
┌───────────────▼──────────────────────────────────────────────────────────┐
│                                                                           │
│  ┌─ Worker node (10.136.11.5) ───────────────────────────────────────┐  │
│                                                                           │
│  ┌─ curl-client-node2 ───────┐     ┌─ http-echo-node2 ───────────────┐ │
│  │ IP: 192.168.42.140        │     │ IP: 192.168.42.141              │ │
│  │ Sends reverse request     │     │ Returns: "hello-from-node2"     │ │
│  └────────────┬───────────────┘     └────────────────▲────────────────┘ │
│               │                                      │                   │
│  ┌────────────▼──────────────────────────────────────┤───────────────┐  │
│  │         ztunnel (10.136.11.5, host network)       │               │  │
│  │                                                    │               │  │
│  │  INBOUND (:15008):                                │               │  │
│  │  ⑥ Receives HBONE from CP ztunnel                │               │  │
│  │  ⑦ Decrypts TLS, delivers to http-echo-node2 ────┘               │  │
│  │                                                                    │  │
│  │  OUTBOUND (:15001):                                               │  │
│  │  Intercepts curl-client-node2 for reverse test                    │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  Host:  eno1: 10.136.11.5/24                                            │
│         Route: 192.168.93.192/26 via 10.136.0.65 proto bird            │
└──────────────────────────────────────────────────────────────────────────┘
```

### IP addresses at each hop (Test 1: node1 → node2)

| Hop | Source IP | Dest IP | Interface | Notes |
|-----|-----------|---------|-----------|-------|
| ① App sends | 192.168.93.200 | 192.168.42.141:8080 | curl-client-node1 eth0 | Original HTTP request |
| ② TPROXY intercept | 192.168.93.200 | 192.168.42.141:8080 | CP host cali* | Redirected to ztunnel:15001 |
| ③ mTLS encrypt | — | — | ztunnel internal | SPIFFE cert for source identity |
| ④ HBONE tunnel | 10.136.0.65 | 10.136.11.5:15008 | CP eno1 → network | TLS 1.3 + HTTP/2 CONNECT |
| ⑤ Network transit | 10.136.0.65 | 10.136.11.5 | physical network | Encrypted payload |
| ⑥ HBONE receive | — | — | worker eno1 | ztunnel terminates TLS |
| ⑦ Deliver to pod | ztunnel | 192.168.42.141:8080 | worker cali* | Decrypted, delivered to pod |

### IP addresses at each hop (Test 2: node2 → node1, reverse)

| Hop | Source IP | Dest IP | Notes |
|-----|-----------|---------|-------|
| ⑧ HBONE tunnel | 10.136.11.5 | 10.136.0.65:15008 | Reverse direction |
| ⑨ Deliver to pod | ztunnel | 192.168.93.201:8080 | http-echo-node1 on CP |

### Pod CIDR routes (Cilium flat network, no overlay)

Example (your IPs may differ):

```
On control-plane:
  192.168.42.128/26 via 10.136.11.5 dev eno1    ← route to worker's pod subnet

On worker:
  192.168.93.192/26 via 10.136.0.65 dev eno1   ← route to control-plane pod subnet
```

## Why this matters

This is the core ztunnel data path for ambient mode across nodes. If same-node works but cross-node fails, the issue is in:
- HBONE tunnel establishment between ztunnel instances
- Network connectivity between nodes (firewall, MTU)
- Certificate exchange between ztunnel instances
- Cilium/CNI cross-node pod routing (direct routes to remote pod CIDRs)

## What it checks

1. curl-client-node1 and http-echo-node2 are on DIFFERENT nodes
2. node1→node2: HTTP request succeeds, returns "hello-from-node2"
3. node2→node1: HTTP request succeeds, returns "hello-from-node1"
4. ztunnel logs show HBONE/CONNECT/inbound/outbound entries

## How to run

```bash
make test-func TEST=ztunnel-cross-node
```

## Expected output

```
>>> Test: ztunnel cross-node traffic (HBONE tunnel)
    Tests pod-to-pod across DIFFERENT nodes via HBONE mTLS tunnel.
      → curl-client-node1 on: snc2-l54-5-s2
      → curl-client-node2 on: snc2-l72-5-s1
      → http-echo-node1 on: snc2-l54-5-s2
      → http-echo-node2 on: snc2-l72-5-s1
      → Test 1: curl-client-node1 → http-echo-node2 @ 192.168.42.141:8080
      → response: hello-from-node2
      → Test 2: curl-client-node2 → http-echo-node1 @ 192.168.93.201:8080
      → response: hello-from-node1
      → ztunnel HBONE/proxy entries (last 15s): 4
    PASS: Cross-node ztunnel: node1->node2 and node2->node1 OK (mTLS HBONE tunnel verified)
```

## Troubleshooting

- Check inter-node ping: `ping <other-node-ip>`
- Check pod CIDR routes: `ip route | grep 192.168`
- Check ztunnel logs: `kubectl logs -n istio-system -l app=ztunnel | grep HBONE`
- Check firewall: port 15008 must be open between nodes
- Check ztunnel certs: `istioctl ztunnel-config certificates`
