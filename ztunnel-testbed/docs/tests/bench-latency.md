# Test: bench-latency

**Script**: `tests/performance/bench-latency.sh`
**Category**: Performance
**Prerequisites**: make deploy (fortio pods running)

## What it tests

Min/Avg/Max/P99 latency in microseconds for varying payloads, HTTP methods, concurrency.

## Why this matters

Measures request latency through ztunnel. Lower concurrency (c=1) for accurate single-request measurement. Compare ambient vs baseline to see mTLS overhead.

## What it checks

- Min/Avg/Max/P99 per payload size
- HTTP GET, GET no-keepalive (TLS handshake cost), POST 1KB
- Concurrency impact at c=1,4,16,64

## How to run

```bash
make bench-latency
```

Or with shorter duration and skip concurrency sweep:

```bash
DURATION=5s SKIP_SWEEP=1 make bench-latency
```

## Expected output

```
Single summary table in .bench-results/bench-latency-*.txt
```

## Troubleshooting

Ensure fortio pods are running, check that ambient and baseline namespaces are correctly labeled.
