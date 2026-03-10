# Test: pod-to-service

**Script**: `tests/functionality/test-pod-to-service.sh`
**Category**: Application
**Prerequisites**: make deploy

## What it tests

HTTP request from curl-client through http-echo ClusterIP Service, testing DNS + kube-proxy + ztunnel end-to-end.

## Network layout

```
┌─ Node: snc2-l54-5-s2 (10.136.0.65) ─────────────────────────────────────┐
│                                                                           │
│  ┌─ curl-client pod ──────────┐     ┌─ http-echo pod ─────────────────┐ │
│  │ IP: 192.168.93.197         │     │ IP: 192.168.93.194              │ │
│  │ eth0                       │     │ eth0, Listens: :8080            │ │
│  │                            │     │                                 │ │
│  │ curl http://http-echo      │     │                                 │ │
│  │  .grimlock.svc.cluster     │     │                                 │ │
│  │  .local:80/                │     │                                 │ │
│  └────────────┬───────────────┘     └────────────────▲────────────────┘ │
│               │                                      │                   │
│  ① DNS lookup: http-echo.grimlock.svc.cluster.local                     │
│     ┌─────────▼─────────────┐                        │                   │
│     │ CoreDNS (10.96.0.10)  │                        │                   │
│     │ Returns: 10.106.69.223│ (ClusterIP)            │                   │
│     └───────────────────────┘                        │                   │
│               │                                      │                   │
│  ② App sends TCP to ClusterIP 10.106.69.223:80      │                   │
│               │                                      │                   │
│  ③ kube-proxy iptables NAT: 10.106.69.223:80 → 192.168.93.194:8080     │
│               │                                      │                   │
│  ┌────────────▼──────────────────────────────────────┤───────────────┐  │
│  │                    ztunnel pod                     │               │  │
│  │                                                    │               │  │
│  │  ④ istio-cni TPROXY intercepts outbound TCP       │               │  │
│  │     → ztunnel:15001                               │               │  │
│  │                                                    │               │  │
│  │  ⑤ ztunnel encrypts with mTLS, delivers locally   │               │  │
│  │     → ztunnel:15008 inbound → http-echo pod ──────┘               │  │
│  │                                                                    │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  Host interfaces:                                                        │
│    eno1: 10.136.0.65/24                                                 │
│    calif73830f3e8a: → curl-client (192.168.93.197)                      │
│    cali4251e27b60f: → http-echo (192.168.93.194)                        │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### IP addresses at each hop

| Hop | Source IP | Dest IP | Port | Notes |
|-----|-----------|---------|------|-------|
| ① DNS query | 192.168.93.197 | 10.96.0.10:53 | UDP | CoreDNS resolves service name |
| ② App sends | 192.168.93.197 | 10.106.69.223:80 | TCP | ClusterIP (virtual) |
| ③ kube-proxy NAT | 192.168.93.197 | 192.168.93.194:8080 | TCP | DNAT to real pod IP |
| ④ TPROXY intercept | 192.168.93.197 | 192.168.93.194:8080 | TCP | Redirected to ztunnel:15001 |
| ⑤ ztunnel delivers | ztunnel | 192.168.93.194:8080 | TCP | mTLS encrypted, delivered to pod |

### Key IPs

| Name | IP | Type |
|------|-----|------|
| curl-client pod | 192.168.93.197 | Pod IP |
| http-echo pod | 192.168.93.194 | Pod IP |
| http-echo Service | 10.106.69.223 | ClusterIP (virtual) |
| CoreDNS | 10.96.0.10 | Service ClusterIP |
| Node | 10.136.0.65 | Physical NIC |

## Why this matters

Standard Kubernetes traffic path: pod → Service → pod. Both hops go through ztunnel with mTLS. If pod-to-pod works but this fails, the issue is in Service resolution (DNS or kube-proxy rules).

## What it checks

1. curl-client pod exists
2. HTTP to `http-echo.grimlock.svc.cluster.local:80` returns expected response
3. Skips if curl-client not deployed

## How to run

```bash
make test-func TEST=pod-to-service
```

## Expected output

```
>>> Test: Pod -> Service -> Pod
    Sends HTTP request via ClusterIP Service. Tests DNS + kube-proxy + ztunnel end-to-end.
      → client=curl-client-xxx, service=http-echo.grimlock (ClusterIP=10.106.69.223)
      → response: hello-from-pod
    PASS: Pod -> Service -> Pod: http-echo service OK (224ms)
```

## Troubleshooting

- Check Service: `kubectl get svc http-echo -n grimlock`
- Check CoreDNS: `kubectl get pods -n kube-system -l k8s-app=kube-dns`
- Check kube-proxy rules: `sudo iptables -t nat -L | grep http-echo`
- Check ztunnel logs: `kubectl logs -n istio-system -l app=ztunnel --tail=20`
