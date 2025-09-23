#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/build"
LOG_FILE="$LOG_DIR/latest.log"

mkdir -p "$LOG_DIR"

TEMP_LOG="$(mktemp)"
EXCERPT_RESULT="$(mktemp)"

cleanup() {
  rm -f "$TEMP_LOG" "$EXCERPT_RESULT"
}
trap cleanup EXIT

# Default build args; allow callers to pass extra xcodebuild flags via "$@".
BUILD_ARGS=(
  -project "GitX.xcodeproj"
  -scheme "Debug"
  -configuration "Debug"
  -destination "generic/platform=macOS"
)

# Run build and capture full, unfiltered output to a temp file.
if xcodebuild "${BUILD_ARGS[@]}" "$@" >"$TEMP_LOG" 2>&1; then
  BUILD_STATUS=0
else
  BUILD_STATUS=$?
fi

# Preserve the full log for exceptional needs.
cp "$TEMP_LOG" "$LOG_FILE"

if [[ "$BUILD_STATUS" -eq 0 ]]; then
  : >"$TEMP_LOG"
  if xcodebuild -project "GitX.xcodeproj" -target "cli tool" -configuration "Release" -arch arm64 build >"$TEMP_LOG" 2>&1; then
    cp "$TEMP_LOG" "$LOG_FILE"
    echo "Build succeeded"
    exit 0
  else
    BUILD_STATUS=$?
    cp "$TEMP_LOG" "$LOG_FILE"
  fi
fi

# Verbatim extraction of diagnostics (errors/warnings) preserving order.
# Broad, case-insensitive patterns to minimize false negatives across Swift/Clang/ld/xcodebuild.
grep -E -i \
  '(^|\s)(error:|warning:|fatal error:)|Undefined symbols for architecture|duplicate symbol|ld: symbol\(s\) not found|linker command failed|library not found for -l|framework not found|Command .* failed with a nonzero exit code|no such module|could not build Objective-C module|error generated\.|No such file or directory|file not found|module map file .* not found|failed to emit precompiled header' \
  "$TEMP_LOG" >"$EXCERPT_RESULT" || true

# Also include xcodebuild’s failure summary block if present (typically concise and near the end).
if grep -q 'The following build commands failed:' "$TEMP_LOG"; then
  sed -n '/The following build commands failed:/,$p' "$TEMP_LOG" >>"$EXCERPT_RESULT"
fi

if [[ -s "$EXCERPT_RESULT" ]]; then
  # Output only the verbatim excerpts; no headers, no commentary.
  cat "$EXCERPT_RESULT"
else
  # Safety net: we failed but matched nothing; direct the developer to the preserved log.
  echo "Build failed but no diagnostics matched known patterns; see $LOG_FILE" >&2
fi

exit "$BUILD_STATUS"
