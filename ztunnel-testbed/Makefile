# =============================================================================
# ztunnel-testbed - Makefile
# =============================================================================
# Convenience targets for common operations
# =============================================================================

.PHONY: setup create install deploy build-images load-images test-func test-perf bench-ambient bench-baseline install-prereqs-baremetal inspect clean help

SHELL := /bin/bash

setup: create install deploy
	@echo "Setup complete. Run: make test-func"

create:
	./scripts/create-cluster.sh

fix-kubeconfig:
	./scripts/fix-kubeconfig.sh

create-baremetal:
	./scripts/create-cluster-baremetal.sh

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
	@echo "  make setup         - Verify cluster + install Istio + deploy sample apps"
	@echo "  make create        - Verify kubectl cluster connectivity (does not create cluster)"
	@echo "  make create-baremetal - Create cluster on bare metal (kubeadm)"
	@echo "  make install-prereqs-baremetal - Show install command for bare metal deps"
	@echo "  make install       - Install Istio ambient only"
	@echo "  make install-cilium - Install Cilium CNI (no Helm, Istio compatible)"
	@echo "  make deploy       - Deploy sample apps only"
	@echo "  make build-images - Build local http-echo, curl-client, fortio images"
	@echo "  make load-images  - Load local images into kind/minikube"
	@echo "  make test-func    - Run functionality tests"
	@echo "  make test-perf    - Run performance tests (ambient + baseline)"
	@echo "  make bench-ambient  - Performance test (ambient only)"
	@echo "  make bench-baseline - Performance test (baseline only)"
	@echo "  make inspect      - Inspect ztunnel state"
	@echo "  make clean        - Uninstall Istio, remove sample apps"
