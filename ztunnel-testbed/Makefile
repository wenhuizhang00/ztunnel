# =============================================================================
# ztunnel-testbed - Makefile
# =============================================================================
# Convenience targets for common operations
# =============================================================================

.PHONY: setup create install deploy test-func test-perf bench-ambient bench-baseline inspect clean help

SHELL := /bin/bash

setup: create install deploy
	@echo "Setup complete. Run: make test-func"

create:
	./scripts/create-cluster.sh

create-baremetal:
	./scripts/create-cluster-baremetal.sh

install:
	./scripts/install-istio.sh

install-cilium:
	./scripts/install-cilium.sh

deploy:
	./scripts/deploy-sample-apps.sh

test-func:
	./scripts/run-functionality-tests.sh

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
	@echo "  make setup       - Create cluster, install Istio, deploy sample apps"
	@echo "  make create      - Verify kubectl cluster connectivity"
	@echo "  make create-baremetal - Create cluster on bare metal (kubeadm)"
	@echo "  make install     - Install Istio ambient only"
	@echo "  make install-cilium - Install Cilium CNI (Istio ambient compatible, no Helm)"
	@echo "  make deploy      - Deploy sample apps only"
	@echo "  make test-func   - Run functionality tests"
	@echo "  make test-perf    - Run performance tests (ambient + baseline)"
	@echo "  make bench-ambient  - Run performance test (ambient only)"
	@echo "  make bench-baseline - Run performance test (baseline only)"
	@echo "  make inspect     - Inspect ztunnel state"
	@echo "  make clean       - Delete cluster and optional cache"
