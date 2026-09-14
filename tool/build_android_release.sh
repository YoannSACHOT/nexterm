#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f android/key.properties ]]; then
  echo "Missing release signing configuration in android/key.properties" >&2
  exit 1
fi

flutter build appbundle \
  --release \
  --obfuscate \
  --split-debug-info=build/symbols/android \
  "$@"
