#!/bin/bash
# Run line staging/unstaging tests
# Silent on success, verbose on failure

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Run Node.js tests
node tests.js

# If we get here, all tests passed
