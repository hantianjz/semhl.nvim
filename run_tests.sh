#!/bin/bash
# Simple test runner for semhl.nvim
# Usage: ./run_tests.sh [nvim_path] [--all]
# Example: ./run_tests.sh              # Run unit tests only
#          ./run_tests.sh --all         # Run all tests including manual
#          ./run_tests.sh /usr/bin/nvim # Use specific nvim

set -e

# Parse arguments
NVIM_BIN="nvim"
RUN_ALL=false

for arg in "$@"; do
  case $arg in
    --all)
      RUN_ALL=true
      ;;
    *)
      NVIM_BIN="$arg"
      ;;
  esac
done

# Check if nvim exists
if ! command -v "$NVIM_BIN" &> /dev/null; then
    echo "Error: Neovim not found at: $NVIM_BIN"
    echo "Usage: $0 [nvim_path]"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "semhl.nvim Test Runner"
echo "========================================="
echo "Neovim: $NVIM_BIN"
$NVIM_BIN --version | head -n1
echo "Test directory: $SCRIPT_DIR/test"
echo "========================================="
echo ""

# Ensure plenary is available
PLENARY_DIR="/tmp/semhl-test/plenary.nvim"
if [ ! -d "$PLENARY_DIR" ]; then
    echo "Installing plenary.nvim for testing..."
    mkdir -p "$(dirname "$PLENARY_DIR")"
    git clone --depth=1 https://github.com/nvim-lua/plenary.nvim.git "$PLENARY_DIR" 2>&1 | grep -v "^Cloning"
    echo "✓ plenary.nvim installed"
    echo ""
fi

# Determine which tests to run
if [ "$RUN_ALL" = true ]; then
    TEST_PATTERN="$SCRIPT_DIR/test"
    echo "Running ALL tests (including manual tests)..."
else
    # Only run tests directly in test/ directory, not subdirectories
    TEST_PATTERN="$SCRIPT_DIR/test/*_spec.lua"
    echo "Running unit tests only..."
    echo "(Use --all to include manual/integration tests)"
fi
echo ""

if [ "$RUN_ALL" = true ]; then
    $NVIM_BIN --headless --noplugin -u NONE \
        -c "set rtp+=$SCRIPT_DIR" \
        -c "set rtp+=$PLENARY_DIR" \
        -c "runtime plugin/plenary.vim" \
        -c "lua package.path='$SCRIPT_DIR/lua/?.lua;' .. package.path" \
        -c "PlenaryBustedDirectory $SCRIPT_DIR/test { minimal_init = '$SCRIPT_DIR/test/minimal_init.lua' }"
else
    # Run only unit tests (files in test/ root, not subdirectories)
    for test_file in $SCRIPT_DIR/test/*_spec.lua; do
        $NVIM_BIN --headless --noplugin -u NONE \
            -c "set rtp+=$SCRIPT_DIR" \
            -c "set rtp+=$PLENARY_DIR" \
            -c "runtime plugin/plenary.vim" \
            -c "lua package.path='$SCRIPT_DIR/lua/?.lua;' .. package.path" \
            -c "PlenaryBustedFile $test_file" || exit 1
    done
fi

exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
    echo "========================================="
    echo "✓ All tests passed!"
    echo "========================================="
else
    echo "========================================="
    echo "✗ Tests failed (exit code: $exit_code)"
    echo "========================================="
fi

exit $exit_code
