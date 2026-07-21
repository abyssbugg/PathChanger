#!/bin/bash
# Coverage Report Generator for PathChanger
# Usage: ./scripts/coverage.sh [--html] [--json] [--threshold N]

set -eo pipefail
cd "$(dirname "$0")/.."

# Default settings
OUTPUT_DIR=".build/coverage"
THRESHOLD=0  # Default: no threshold enforcement

# Parse arguments
GENERATE_HTML=false
GENERATE_JSON=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --html)
            GENERATE_HTML=true
            shift
            ;;
        --json)
            GENERATE_JSON=true
            shift
            ;;
        --threshold)
            THRESHOLD=$2
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--html] [--json] [--threshold N]"
            exit 1
            ;;
    esac
done

echo "=================================================="
echo "PathChanger Test Coverage Report"
echo "=================================================="
echo ""

# Clean previous coverage data
rm -rf "$OUTPUT_DIR" 2>/dev/null || true
mkdir -p "$OUTPUT_DIR"

# Run tests with coverage enabled
echo "Running tests with code coverage..."
swift test --enable-code-coverage 2>&1 | tee "$OUTPUT_DIR/test-output.log"

# Find the profdata file
PROFDATA=$(find .build -name "default.profdata" -type f 2>/dev/null | head -1)
if [ -z "$PROFDATA" ]; then
    echo "Error: Could not find coverage data. Tests may have failed."
    exit 1
fi

# Find the test binary
TEST_BINARY=$(find .build -name "PathChangerPackageTests" -type f -perm +111 2>/dev/null | head -1)
if [ -z "$TEST_BINARY" ]; then
    # Try alternate path
    TEST_BINARY=".build/debug/PathChangerPackageTests.xctest/Contents/MacOS/PathChangerPackageTests"
fi

if [ ! -f "$TEST_BINARY" ]; then
    echo "Error: Could not find test binary."
    exit 1
fi

echo ""
echo "Generating coverage report..."
echo ""

# Generate text summary
echo "=== Coverage Summary ===" > "$OUTPUT_DIR/summary.txt"
# Fail closed: report generation feeds the threshold gate below, so a failure
# here must not be swallowed (previously `|| true` let coverage pass silently).
xcrun llvm-cov report "$TEST_BINARY" -instr-profile="$PROFDATA" \
    -ignore-filename-regex="Tests/|.build/" >> "$OUTPUT_DIR/summary.txt"

cat "$OUTPUT_DIR/summary.txt"

# Generate LCOV format
echo ""
echo "Generating LCOV format..."
xcrun llvm-cov export "$TEST_BINARY" \
    -instr-profile="$PROFDATA" \
    -format=lcov \
    -ignore-filename-regex="Tests/|.build/" \
    > "$OUTPUT_DIR/coverage.lcov" 2>/dev/null || true

# Generate JSON if requested
if [ "$GENERATE_JSON" = true ]; then
    echo "Generating JSON format..."
    xcrun llvm-cov export "$TEST_BINARY" \
        -instr-profile="$PROFDATA" \
        -format=text \
        -ignore-filename-regex="Tests/|.build/" \
        > "$OUTPUT_DIR/coverage.json" 2>/dev/null || true
fi

# Generate HTML if requested
if [ "$GENERATE_HTML" = true ]; then
    echo "Generating HTML report..."
    xcrun llvm-cov show "$TEST_BINARY" \
        -instr-profile="$PROFDATA" \
        -format=html \
        -output-dir="$OUTPUT_DIR/html" \
        -ignore-filename-regex="Tests/|.build/" 2>/dev/null || true
    echo "HTML report: $OUTPUT_DIR/html/index.html"
fi

# Extract coverage percentage
COVERAGE_LINE=$(grep "TOTAL" "$OUTPUT_DIR/summary.txt" 2>/dev/null || echo "")
if [ -z "$COVERAGE_LINE" ]; then
    # Fail closed: if a threshold was requested we must not silently pass when
    # coverage could not be parsed (e.g. report generation produced no TOTAL).
    if [ "$THRESHOLD" -gt 0 ]; then
        echo "" >&2
        echo "ERROR: Coverage threshold ${THRESHOLD}% requested but total coverage could not be determined" >&2
        exit 1
    fi
else
    COVERAGE_PCT=$(echo "$COVERAGE_LINE" | awk '{print $4}' | tr -d '%')
    echo ""
    echo "=== Total Coverage: ${COVERAGE_PCT}% ==="

    # Check threshold
    if [ "$THRESHOLD" -gt 0 ]; then
        COVERAGE_INT=${COVERAGE_PCT%.*}
        if [ "$COVERAGE_INT" -lt "$THRESHOLD" ]; then
            echo ""
            echo "ERROR: Coverage ${COVERAGE_PCT}% is below threshold ${THRESHOLD}%"
            exit 1
        else
            echo "PASS: Coverage meets threshold of ${THRESHOLD}%"
        fi
    fi
fi

echo ""
echo "Coverage reports generated in: $OUTPUT_DIR/"
echo "  - summary.txt: Text summary"
echo "  - coverage.lcov: LCOV format (for CI integration)"
if [ "$GENERATE_HTML" = true ]; then
    echo "  - html/: Interactive HTML report"
fi
if [ "$GENERATE_JSON" = true ]; then
    echo "  - coverage.json: JSON format"
fi
echo ""
echo "Done!"
