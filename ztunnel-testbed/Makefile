# =============================================================================
# ztunnel-testbed - Makefile
# =============================================================================
# Convenience targets for common operations
# =============================================================================

.PHONY: setup create install deploy build-images load-images test-func test-list test-perf bench-ambient bench-baseline install-prereqs-baremetal inspect clean help

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

test-perf:
	./scripts/run-performance-tests.sh

bench-ambient:
	MODE=ambient ./scripts/run-performance-tests.sh

bench-baseline:
	MODE=baseline ./scripts/run-performance-tests.sh

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
	@echo "    make test-perf              - Run performance tests (ambient + baseline)"
	@echo "    make bench-ambient          - Performance test (ambient only)"
	@echo "    make bench-baseline         - Performance test (baseline only)"
	@echo ""
	@echo "  Other:"
	@echo "    make build-images       - Build local http-echo, curl-client, fortio images"
	@echo "    make load-images        - Load local images into kind/minikube"
	@echo "    make inspect            - Inspect ztunnel state"
	@echo "    make clean              - Uninstall Istio, remove sample apps"
