#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Run functionality tests
# =============================================================================
#
# Test runner with three modes:
#   1. Interactive menu (default when run in a terminal with no arguments)
#   2. Run all tests (--all flag, for CI/automation)
#   3. Filter by name (substring match, e.g. "pod" matches pod-to-pod and pod-to-service)
#
# Usage:
#   ./scripts/run-functionality-tests.sh              # interactive menu
#   ./scripts/run-functionality-tests.sh --all        # run all tests (non-interactive)
#   ./scripts/run-functionality-tests.sh cluster      # run tests matching "cluster"
#   ./scripts/run-functionality-tests.sh pod-to-pod   # run a single test
#   ./scripts/run-functionality-tests.sh --list       # list available tests
#   TEST=cluster-ready make test-func                 # via Makefile
#
# Each test script in tests/functionality/test-*.sh is auto-discovered.
# Exit code: 0 if all tests pass, 1 if any test fails.
#
# See docs/TESTING.md for full documentation.
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TEST_DIR="${PROJECT_ROOT}/tests/functionality"
FILTER="${TEST:-${1:-}}"

# Collect available tests
declare -a TEST_NAMES=()
declare -a TEST_PATHS=()
for t in "${TEST_DIR}"/test-*.sh; do
  TEST_NAMES+=("$(basename "$t" .sh | sed 's/^test-//')")
  TEST_PATHS+=("$t")
done

# ---- List mode ----
if [[ "$FILTER" == "--list" ]] || [[ "$FILTER" == "-l" ]]; then
  echo "Available functionality tests:"
  echo ""
  for i in "${!TEST_NAMES[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${TEST_NAMES[$i]}"
  done
  echo ""
  echo "Usage:"
  echo "  $0                    # interactive menu"
  echo "  $0 --all              # run all tests"
  echo "  $0 <filter>           # run tests matching filter"
  echo "  TEST=<filter> $0      # same, via env var"
  exit 0
fi

# ---- Interactive menu (no args, stdin is a terminal) ----
if [[ -z "$FILTER" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
  echo ""
  echo -e "${BLUE}Functionality Tests${NC}"
  echo "─────────────────────────────────────────"
  echo ""
  printf "  %2d) %s\n" "0" "Run ALL tests"
  for i in "${!TEST_NAMES[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${TEST_NAMES[$i]}"
  done
  echo ""
  read -rp "Select test(s) [0=all, or numbers separated by spaces]: " selection

  if [[ -z "$selection" ]] || [[ "$selection" == "0" ]]; then
    FILTER="--all"
  else
    SELECTED_INDICES=()
    for s in $selection; do
      if [[ "$s" =~ ^[0-9]+$ ]] && [[ "$s" -ge 1 ]] && [[ "$s" -le "${#TEST_NAMES[@]}" ]]; then
        SELECTED_INDICES+=("$((s-1))")
      else
        log_warn "Invalid selection: $s (skipping)"
      fi
    done
    if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
      log_error "No valid tests selected."
      exit 1
    fi
  fi
fi

ensure_kubectl_context

# ---- Run tests ----
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TESTS_TOTAL=0
FAILED_NAMES=()

suite_start=$(date +%s)

run_test() {
  local path="$1"
  local name="$2"
  ((TESTS_TOTAL++)) || true
  [[ -x "$path" ]] || chmod +x "$path"
  if "$path"; then
    ((TESTS_PASSED++)) || true
  else
    ((TESTS_FAILED++)) || true
    FAILED_NAMES+=("$name")
  fi
}

if [[ -n "${SELECTED_INDICES+x}" ]]; then
  # Interactive: run selected tests
  log_info "Running ${#SELECTED_INDICES[@]} selected test(s)..."
  for idx in "${SELECTED_INDICES[@]}"; do
    run_test "${TEST_PATHS[$idx]}" "${TEST_NAMES[$idx]}"
  done
elif [[ "$FILTER" == "--all" ]] || [[ "$FILTER" == "-a" ]]; then
  log_info "Running all functionality tests..."
  for i in "${!TEST_NAMES[@]}"; do
    run_test "${TEST_PATHS[$i]}" "${TEST_NAMES[$i]}"
  done
else
  # Filter mode
  log_info "Running functionality tests matching: ${FILTER}"
  matched=0
  for i in "${!TEST_NAMES[@]}"; do
    if [[ "${TEST_NAMES[$i]}" == *"$FILTER"* ]]; then
      run_test "${TEST_PATHS[$i]}" "${TEST_NAMES[$i]}"
      ((matched++)) || true
    fi
  done
  if [[ $matched -eq 0 ]]; then
    log_error "No tests matched filter: $FILTER"
    echo "Available: ${TEST_NAMES[*]}"
    exit 1
  fi
fi

suite_elapsed=$(( $(date +%s) - suite_start ))

# ---- Summary ----
echo ""
echo "=========================================="
if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}Summary: $TESTS_PASSED passed, $TESTS_FAILED failed ($TESTS_TOTAL tests in ${suite_elapsed}s)${NC}"
else
  echo -e "${RED}Summary: $TESTS_PASSED passed, $TESTS_FAILED failed ($TESTS_TOTAL tests in ${suite_elapsed}s)${NC}"
  echo ""
  echo "Failed:"
  for name in "${FAILED_NAMES[@]}"; do
    echo "  - $name"
  done
  echo ""
  echo "Re-run failed:"
  echo "  $0 ${FAILED_NAMES[0]}"
fi
echo "=========================================="
[[ $TESTS_FAILED -eq 0 ]]
