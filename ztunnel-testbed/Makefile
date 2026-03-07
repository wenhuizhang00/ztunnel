# =============================================================================
# ztunnel-testbed - Makefile
# =============================================================================
# Convenience targets for common operations
# =============================================================================

.PHONY: setup create install deploy build-images load-images test-func test-list test-perf bench-throughput bench-latency bench-throughput-cross bench-latency-cross bench-ambient bench-baseline bench-quick install-prereqs-baremetal inspect clean help

SHELL := /bin/bash

setup: create install deploy
	@echo "Setup complete. Run: make test-func"

create:
	./scripts/create-cluster.sh

create-baremetal:
	./scripts/create-cluster-baremetal.sh

# Multi-node: create cluster + auto-join worker(s)
#   make create-baremetal-multi WORKER=10.136.0.75
#   make create-baremetal-multi WORKER="10.136.0.75,10.136.0.76"
create-baremetal-multi:
	WORKER_NODES=$(WORKER) ./scripts/create-cluster-baremetal.sh

install-prereqs-baremetal:
	@echo "Run on each node (control-plane and workers) with sudo:"
	@echo "  sudo ./scripts/install-baremetal-prereqs.sh"

install:
	./scripts/install-istio.sh

install-cilium:
	./scripts/install-cilium.sh

deploy:
	./scripts/deploy-sample-apps.sh

build-images:
	./scripts/build-images.sh

load-images:
	./scripts/load-images.sh

# Functionality tests: interactive menu, or filter with TEST=<name>
#   make test-func              # interactive: pick tests from menu
#   make test-func TEST=--all   # run all (non-interactive)
#   make test-func TEST=pod     # run tests matching "pod"
test-func:
	./scripts/run-functionality-tests.sh $(TEST)

test-list:
	./scripts/run-functionality-tests.sh --list

# Performance tests
#   make test-perf                           # all benchmarks (auto-detects topology)
#   make bench-throughput                    # throughput only
#   make bench-latency                       # latency only
#   make bench-throughput-cross              # throughput, cross-node (multi-node)
#   make bench-latency-cross                 # latency, cross-node (multi-node)
#   make bench-ambient                       # ambient only
#   make bench-baseline                      # baseline only
#   make bench-quick                         # quick run (5s, skip sweep)
test-perf:
	./scripts/run-performance-tests.sh

bench-throughput:
	BENCH=throughput ./scripts/run-performance-tests.sh

bench-latency:
	BENCH=latency ./scripts/run-performance-tests.sh

bench-throughput-cross:
	BENCH=throughput TOPOLOGY=cross-node ./scripts/run-performance-tests.sh

bench-latency-cross:
	BENCH=latency TOPOLOGY=cross-node ./scripts/run-performance-tests.sh

bench-ambient:
	MODE=ambient ./scripts/run-performance-tests.sh

bench-baseline:
	MODE=baseline ./scripts/run-performance-tests.sh

bench-quick:
	DURATION=5s SKIP_SWEEP=1 ./scripts/run-performance-tests.sh

inspect:
	./scripts/ztunnel-inspect.sh all

clean:
	./scripts/cleanup.sh

help:
	@echo "ztunnel-testbed targets:"
	@echo ""
	@echo "  Setup:"
	@echo "    make setup              - Verify cluster + install Istio + deploy sample apps"
	@echo "    make create             - Verify kubectl cluster connectivity"
	@echo "    make create-baremetal   - Create single-node cluster on bare metal (kubeadm)"
	@echo "    make create-baremetal-multi WORKER=10.136.0.75 - Create multi-node cluster"
	@echo "    make install-prereqs-baremetal - Show install command for bare metal deps"
	@echo "    make install            - Install Istio ambient only"
	@echo "    make install-cilium     - Install Cilium CNI (no Helm, Istio compatible)"
	@echo "    make deploy             - Deploy sample apps only"
	@echo ""
	@echo "  Tests:"
	@echo "    make test-func              - Interactive: pick tests from menu"
	@echo "    make test-func TEST=--all   - Run all functionality tests"
	@echo "    make test-func TEST=pod     - Run tests matching 'pod'"
	@echo "    make test-list              - List available tests"
	@echo "    make test-perf              - Full performance suite (auto-detects topology)"
	@echo "    make bench-throughput       - Throughput test (single-node)"
	@echo "    make bench-latency          - Latency test (single-node)"
	@echo "    make bench-throughput-cross  - Throughput test (cross-node, multi-node)"
	@echo "    make bench-latency-cross     - Latency test (cross-node, multi-node)"
	@echo "    make bench-ambient          - All benchmarks (ambient only)"
	@echo "    make bench-baseline         - All benchmarks (baseline only)"
	@echo "    make bench-quick            - Quick benchmark (5s, no sweep)"
	@echo ""
	@echo "  Other:"
	@echo "    make build-images       - Build local http-echo, curl-client, fortio images"
	@echo "    make load-images        - Load local images into kind/minikube"
	@echo "    make inspect            - Inspect ztunnel state"
	@echo "    make clean              - Uninstall Istio, remove sample apps"
