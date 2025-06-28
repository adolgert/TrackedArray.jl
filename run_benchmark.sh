#!/bin/bash

# Get the current git hash
GIT_HASH=$(git rev-parse --short HEAD)

# Check if we're in a git repo
if [ $? -ne 0 ]; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Check if there are uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "Warning: There are uncommitted changes in the repository"
    GIT_HASH="${GIT_HASH}-dirty"
fi

# Create output filename
OUTPUT_FILE="benchmark_${GIT_HASH}.txt"

# Get current date and time
DATETIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

echo "Running benchmarks for commit: ${GIT_HASH}"
echo "Output will be saved to: ${OUTPUT_FILE}"

# Run the benchmark and save output
{
    echo "Benchmark Results"
    echo "================="
    echo "Date: ${DATETIME}"
    echo "Git Hash: ${GIT_HASH}"
    echo ""
    echo "Git Status:"
    git status --short
    echo ""
    echo "Benchmark Output:"
    echo "-----------------"
    julia --project=. test/benchmark.jl "$@"
} > "${OUTPUT_FILE}" 2>&1

# Check if benchmark was successful
if [ $? -eq 0 ]; then
    echo "Benchmark completed successfully"
    echo "Results saved to: ${OUTPUT_FILE}"
else
    echo "Benchmark failed. Check ${OUTPUT_FILE} for errors"
    exit 1
fi