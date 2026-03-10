# Test: bench-throughput

**Script**: `tests/performance/bench-throughput.sh`
**Category**: Performance
**Prerequisites**: make deploy (fortio pods running)

## What it tests

Maximum QPS/Kpps/Mbps for varying payload sizes and concurrency.

## Why this matters

Measures raw throughput capacity through ztunnel. Compares ambient (encrypted) vs baseline (direct).

## What it checks

- QPS, Kpps, Mbps for 64/128/256/512/1024/1500 byte payloads
- Optional concurrency sweep at c=1,4,8,16,32,64,128

## How to run

```bash
make bench-throughput
```

Or with shorter duration and skip concurrency sweep:

```bash
DURATION=5s SKIP_SWEEP=1 make bench-throughput
```

## Expected output

```
Report written to .bench-results/bench-throughput-*.txt
```

## Troubleshooting

Ensure fortio pods are running (`kubectl get pods -n grimlock`), check ambient vs baseline namespace labels.
