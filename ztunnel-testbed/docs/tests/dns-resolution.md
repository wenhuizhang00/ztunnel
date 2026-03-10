# Test: dns-resolution

**Script**: `tests/functionality/test-dns-resolution.sh`
**Category**: Application
**Prerequisites**: Sample apps deployed

## What it tests

CoreDNS resolves Kubernetes service names from inside pods in the ambient namespace.

## Network layout

```
┌─ Node ─────────────────────────────────────────────────────────────────┐
│                                                                         │
│  ┌─ curl-client pod ──────┐                                            │
│  │ IP: 192.168.93.197     │                                            │
│  │ /etc/resolv.conf:      │                                            │
│  │   nameserver 10.96.0.10│                                            │
│  │   search grimlock.svc  │                                            │
│  │     .cluster.local     │                                            │
│  └──────────┬─────────────┘                                            │
│             │                                                           │
│   ① nslookup kubernetes.default.svc.cluster.local                      │
│             │                                                           │
│   ② UDP 192.168.93.197 → 10.96.0.10:53                                │
│     (ClusterIP of kube-dns Service)                                    │
│             │                                                           │
│   ③ kube-proxy DNAT: 10.96.0.10 → 192.168.93.134:53 (CoreDNS pod)    │
│             │                                                           │
│   ┌─────────▼──────────────┐                                           │
│   │ CoreDNS pod            │                                           │
│   │ IP: 192.168.93.134    │                                           │
│   │ Returns:               │                                           │
│   │  kubernetes.default    │                                           │
│   │  → 10.96.0.1          │                                           │
│   │  http-echo.grimlock   │                                           │
│   │  → 10.106.69.223      │                                           │
│   └────────────────────────┘                                           │
│                                                                         │
│  Note: DNS traffic (UDP) goes through ztunnel too in ambient mode.     │
│  ztunnel intercepts all TCP/UDP from ambient pods.                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key IPs

| Name | IP | Type |
|------|-----|------|
| kube-dns Service | 10.96.0.10 | ClusterIP |
| CoreDNS pod | 192.168.93.134 | Pod IP |
| kubernetes.default | 10.96.0.1 | API server ClusterIP |
| http-echo Service | 10.106.69.223 | ClusterIP |

## Why this matters

Kubernetes services are accessed by DNS name. If DNS is broken, pods can't discover services. In ambient mode, ztunnel intercepts all traffic including DNS. This test confirms DNS works end-to-end.

## What it checks

1. `kubernetes.default.svc.cluster.local` resolves (API server VIP 10.96.0.1)
2. `http-echo.grimlock.svc.cluster.local` resolves (http-echo Service ClusterIP)
3. Skips if curl-client pod not found

## How to run

```bash
make test-func TEST=dns-resolution
```

## Expected output

```
>>> Test: DNS resolution inside pods
    Checks CoreDNS resolves service names from inside ambient pods.
      → client pod: curl-client-xxx
      → kubernetes.default lookup: ... Address: 10.96.0.1
      → http-echo.grimlock lookup: ... Address: 10.106.69.223
    PASS: DNS resolution OK (kubernetes.default + http-echo.grimlock)
```

## Troubleshooting

- Check CoreDNS: `kubectl get pods -n kube-system -l k8s-app=kube-dns`
- Check DNS from pod: `kubectl exec -n grimlock deploy/curl-client -- nslookup kubernetes.default`
- Check kube-dns Service: `kubectl get svc kube-dns -n kube-system`
