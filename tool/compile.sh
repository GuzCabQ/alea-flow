#!/usr/bin/env bash
# Compile the alea_flow CLI to a native executable. Eliminates Dart VM cold
# start (~600ms → ~30ms) — important because every skill invocation calls
# the CLI.
#
# Output: bin/aflow (executable). Add to PATH or symlink as needed.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT="bin/aflow"
SRC="bin/aflow.dart"

echo "Compiling $SRC -> $OUT"
dart compile exe "$SRC" -o "$OUT"
echo "Done. Try: $OUT --help"
