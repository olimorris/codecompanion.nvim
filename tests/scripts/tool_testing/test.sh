#!/usr/bin/env bash

# CodeCompanion Tool Testing Wrapper Script
# Provides convenient shortcuts for running tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NVIM="${NVIM:-nvim}"

# Load API keys from .env if present
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

# Colors for output
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
RED='\033[0;31m'
YELLOW='\033[1;33m'


colorize() {
    awk -v RED="$RED" -v GREEN="$GREEN" -v YELLOW="$YELLOW" -v CYAN="$CYAN" -v BOLD="$BOLD" -v NC="$NC" '
    {
        line = $0
        # Scenario dispatch line: "  RUN model :: scenario"
        if (line ~ /  RUN /) {
            n = split(line, parts, " :: ")
            sub(/.*/, YELLOW parts[1] NC " :: " CYAN parts[2] NC, line)
        }
        # Test result patterns
        gsub(/✓ PASS/, GREEN "✓ PASS" NC, line)
        gsub(/✗ FAIL/, RED "✗ FAIL" NC, line)
        gsub(/✗ ERROR/, RED "✗ ERROR" NC, line)
        gsub(/✓ SUCCESS/, GREEN "✓ SUCCESS" NC, line)
        gsub(/✗ FAILED/, RED "✗ FAILED" NC, line)

        # Individual check marks (for test_setup)
        gsub(/  ✓ /, GREEN "  ✓ " NC, line)
        gsub(/  ✗ /, RED "  ✗ " NC, line)

        # Color numbers in summary
        if (match(line, /Passed: [0-9]+/)) {
            sub(/Passed: [0-9]+/, "Passed: " GREEN substr(line, RSTART + 8, RLENGTH - 8) NC, line)
        }
        if (match(line, /Failed: [0-9]+/)) {
            sub(/Failed: [0-9]+/, "Failed: " RED substr(line, RSTART + 8, RLENGTH - 8) NC, line)
        }
        if (match(line, /Errors: [0-9]+/)) {
            sub(/Errors: [0-9]+/, "Errors: " RED substr(line, RSTART + 8, RLENGTH - 8) NC, line)
        }
        if (match(line, /Success Rate: [0-9.]+%/)) {
            sub(/Success Rate: [0-9.]+%/, "Success Rate: " GREEN substr(line, RSTART + 14, RLENGTH - 14) NC, line)
        }

        print line
    }'
}

print_usage() {
    cat << EOF
Usage: $0 [command] [options]

Commands:
    run [options]           Run tests (default command)
    verify                  Verify setup and dependencies
    setup                   Setup configuration from template
    clean                   Remove old test results
    results                 Show latest test results
    failures                Show only failed/errored tests with details
    help                    Show this help message

Options for 'run':
    --adapter=<name>        Run only specific adapter (e.g., openai, anthropic)
    --model=<name>          Run only specific model (e.g., gpt-4o, claude-3.5)
    --scenario=<name>       Run only specific scenario
    --tool=<name>           Run only scenarios for a specific tool (e.g., insert_edit_into_file, read_file)
    --csv                   Append results to a CSV file (path from config or results_dir/results.csv)
    --delay=<ms>            Delay between scenarios in milliseconds (default: 0)
    --verbose               Show detailed output
    --all                   Run all enabled adapters with all scenarios
    --use-config            Use full Neovim config instead of minimal setup

Examples:
    $0 verify
    $0 verify --use-config
    $0 run --adapter=openai
    $0 run --adapter=openai --model=gpt-4o
    $0 run --adapter=openai --use-config
    $0 run --adapter=anthropic --verbose
    $0 run --model=claude --verbose
    $0 run --scenario="Simple file edit"
    $0 run --tool=insert_edit_into_file
    $0 run --adapter=openai --delay=2000
    $0 setup
    $0 results
    $0 failures

Environment Variables:
    OPENAI_API_KEY          OpenAI API key
    ANTHROPIC_API_KEY       Anthropic API key
    AZURE_OPENAI_API_KEY    Azure OpenAI API key
    OPENROUTER_API_KEY      OpenRouter API key

EOF
}

check_config() {
    if [ ! -f "$SCRIPT_DIR/config.local.lua" ]; then
        echo -e "${YELLOW}Warning: config.local.lua not found${NC}"
        echo "Run '$0 setup' to create it from template"
        echo ""
        return 1
    fi
    return 0
}

check_nvim() {
    if ! command -v "$NVIM" &> /dev/null; then
        echo -e "${RED}Error: Neovim not found${NC}"
        echo "Install Neovim or set NVIM environment variable"
        exit 1
    fi
}

cmd_setup() {
    echo "Setting up configuration..."

    if [ -f "$SCRIPT_DIR/config.local.lua" ]; then
        echo -e "${YELLOW}Warning: config.local.lua already exists${NC}"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Setup cancelled"
            exit 0
        fi
    fi

    if [ ! -f "$SCRIPT_DIR/config.local.lua.example" ]; then
        echo -e "${RED}Error: config.local.lua.example not found${NC}"
        exit 1
    fi

    cp "$SCRIPT_DIR/config.local.lua.example" "$SCRIPT_DIR/config.local.lua"
    echo -e "${GREEN}✓ Created config.local.lua${NC}"
    echo ""
    echo "Edit the file to add your API keys:"
    echo "  $SCRIPT_DIR/config.local.lua"
    echo ""
    echo "Or set environment variables:"
    echo "  export OPENAI_API_KEY='sk-...'"
    echo "  export ANTHROPIC_API_KEY='sk-ant-...'"
}

cmd_verify() {
    check_nvim

    echo "Verifying CodeCompanion setup..."
    echo "===================================="
    echo ""

    # Ensure we run from plugin root
    cd "$PLUGIN_ROOT"

    # Check if using full config
    local use_config=false
    for arg in "$@"; do
        if [ "$arg" = "--use-config" ]; then
            use_config=true
            break
        fi
    done

    # Run setup verification
    if [ "$use_config" = true ]; then
        if "$NVIM" --headless +"luafile $SCRIPT_DIR/setup_tests.lua" +q 2>&1 | colorize; then
            echo ""
            echo -e "${GREEN}✓ Setup verified successfully${NC}"
            exit 0
        else
            exit_code=$?
            echo ""
            echo -e "${RED}✗ Setup verification failed${NC}"
            exit $exit_code
        fi
    else
        echo -e "${GREEN}✓${NC} Using minimal setup..."
        if "$NVIM" -l "$SCRIPT_DIR/setup_tests.lua" 2>&1 | colorize; then
            echo ""
            echo -e "${GREEN}✓ Setup verified successfully${NC}"
            exit 0
        else
            exit_code=$?
            echo ""
            echo -e "${RED}✗ Setup verification failed${NC}"
            exit $exit_code
        fi
    fi
}

cmd_run() {
    check_nvim

    # Check config but don't fail - env vars might be set
    check_config || true

    # Ensure we run from plugin root
    cd "$PLUGIN_ROOT"

    # Check if using full config
    local use_config=false
    local test_args=""
    for arg in "$@"; do
        if [ "$arg" = "--use-config" ]; then
            use_config=true
        else
            test_args="$test_args $arg"
        fi
    done

    # Build and run command with color post-processing
    if [ "$use_config" = true ]; then
        local nvim_cmd="$NVIM --headless +'luafile $SCRIPT_DIR/run_tests.lua' +q"
        eval "$nvim_cmd" 2>&1 | colorize
        exit_code=${PIPESTATUS[0]}
        if [ $exit_code -eq 0 ]; then
            echo ""
            echo -e "${GREEN}✓ All tests passed${NC}"
            exit 0
        else
            echo ""
            echo -e "${RED}✗ Tests failed (exit code: $exit_code)${NC}"
            exit $exit_code
        fi
    else
        local nvim_cmd="$NVIM -l $SCRIPT_DIR/run_tests.lua$test_args"
        eval "$nvim_cmd" 2>&1 | colorize
        exit_code=${PIPESTATUS[0]}
        if [ $exit_code -eq 0 ]; then
            echo ""
            echo -e "${GREEN}✓ All tests passed${NC}"
            exit 0
        else
            echo ""
            echo -e "${RED}✗ Tests failed (exit code: $exit_code)${NC}"
            exit $exit_code
        fi
    fi
}

cmd_clean() {
    local results_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/codecompanion_tests"

    if [ ! -d "$results_dir" ]; then
        echo "No test results found"
        exit 0
    fi

    echo "Cleaning test results from: $results_dir"
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$results_dir"
        echo -e "${GREEN}✓ Test results cleaned${NC}"
    else
        echo "Clean cancelled"
    fi
}

cmd_results() {
    check_nvim

    local results_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/codecompanion_tests"

    if [ ! -d "$results_dir" ]; then
        echo "No test results found"
        exit 0
    fi

    # Find latest summary file
    local latest_summary=$(find "$results_dir" -name "summary_*.json" -type f | sort -r | head -n 1)

    if [ -z "$latest_summary" ]; then
        echo "No summary file found"
        exit 1
    fi

    echo "Latest test results: $latest_summary"
    echo "===================================="
    echo ""

    # Use jq if available, otherwise use nvim
    if command -v jq &> /dev/null; then
        cat "$latest_summary" | jq '.summary'
        echo ""
        echo "Detailed results:"
        cat "$latest_summary" | jq -r '.results[] | "\(.adapter)/\(.scenario): \(if .success then "\u001b[0;32m✓ PASS\u001b[0m" else "\u001b[0;31m✗ FAIL\u001b[0m" end)"'
    else
        # Fallback to basic display
        cat "$latest_summary"
    fi

    echo ""
    echo "Full logs in: $results_dir"
}

cmd_failures() {
    check_nvim

    local results_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/codecompanion_tests"

    if [ ! -d "$results_dir" ]; then
        echo "No test results found"
        exit 0
    fi

    # Find latest summary file
    local latest_summary=$(find "$results_dir" -name "summary_*.json" -type f | sort -r | head -n 1)

    if [ -z "$latest_summary" ]; then
        echo "No summary file found"
        exit 1
    fi

    echo "Latest test failures: $latest_summary"
    echo "===================================="
    echo ""

    # Use jq if available
    if command -v jq &> /dev/null; then
        local has_failures=$(cat "$latest_summary" | jq -r '.summary | (.failed + .errors) > 0')

        if [ "$has_failures" = "false" ]; then
            echo -e "${GREEN}✓ No failures! All tests passed.${NC}"
            echo ""
            cat "$latest_summary" | jq '.summary'
            exit 0
        fi

        # Show summary
        echo "Summary:"
        cat "$latest_summary" | jq '.summary'
        echo ""
        echo "===================================="
        echo -e "${RED}Failed/Errored Tests:${NC}"
        echo "===================================="
        echo ""

        # Extract failed/errored results
        cat "$latest_summary" | jq -r '.results[] | select(.success == false) |
            "\(.adapter)/\(.model) - \(.scenario):",
            "  Status: \u001b[0;31m✗ \(if .error then "ERROR" else "FAIL" end)\u001b[0m",
            (if .error then "  Error: \(.error)" else empty end),
            "  Duration: \(.duration_ms / 1000)s",
            (if .result_file then "  File: \(.result_file)" else "  File: N/A" end),
            ""'

        # Find actual result files for failed tests
        echo ""
        echo "===================================="
        echo "Detailed Result Files:"
        echo "===================================="

        # Get list of failed test identifiers
        local failed_tests=$(cat "$latest_summary" | jq -r '.results[] | select(.success == false) |
            "\(.adapter)_\(.model | gsub("/"; "_") | gsub("-"; "_"))_\(.scenario | gsub(" "; "_"))"')

        # Find matching files
        while IFS= read -r test_id; do
            if [ -n "$test_id" ]; then
                # Find files matching this test (most recent first)
                local matching_files=$(find "$results_dir" -type f -name "*${test_id}*.json" ! -name "summary_*" | sort -r | head -n 1)
                if [ -n "$matching_files" ]; then
                    echo "$matching_files"
                fi
            fi
        done <<< "$failed_tests"

    else
        # Fallback without jq - just grep for success: false
        echo "Searching for failures (install jq for better output)..."
        echo ""

        # Count failures
        local total_files=$(find "$results_dir" -type f -name "*.json" ! -name "summary_*" | wc -l)
        echo "Scanning $total_files result files..."
        echo ""

        # Find failed result files
        for file in "$results_dir"/*.json; do
            if [ -f "$file" ] && [ "$(basename "$file")" != "summary_"* ]; then
                if grep -q '"success": false' "$file" 2>/dev/null; then
                    echo -e "${RED}✗ FAILED:${NC} $(basename "$file")"
                    echo "  Path: $file"
                    # Try to extract error
                    local error=$(grep -o '"error": "[^"]*"' "$file" 2>/dev/null | head -1)
                    if [ -n "$error" ]; then
                        echo "  $error"
                    fi
                    echo ""
                fi
            fi
        done
    fi

    echo ""
    echo "===================================="
    echo ""
    echo "To view detailed results:"
    echo "  cat <file_path> | jq ."
    echo ""
    echo "To view specific error:"
    echo "  cat <file_path> | jq '.error'"
}

# Main script logic
COMMAND="${1:-run}"
shift || true

case "$COMMAND" in
    verify)
        cmd_verify "$@"
        ;;
    run)
        cmd_run "$@"
        ;;
    setup)
        cmd_setup
        ;;
    clean)
        cmd_clean
        ;;
    results)
        cmd_results
        ;;
    failures)
        cmd_failures
        ;;
    help|--help|-h)
        print_usage
        exit 0
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$COMMAND'${NC}"
        echo ""
        print_usage
        exit 1
        ;;
esac
