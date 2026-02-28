#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

suites=(
  "$TEST_DIR/test_core.sh"
  "$TEST_DIR/test_providers.sh"
  "$TEST_DIR/test_history.sh"
  "$TEST_DIR/test_config.sh"
  "$TEST_DIR/test_commands.sh"
)

for suite in "${suites[@]}"; do
  echo "Running: $(basename "$suite")"
  bash "$suite"
done

echo "tests/test_ai.sh: OK"
