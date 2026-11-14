#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp/}mac-island-checks.XXXXXX")
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -parse-as-library Sources/MacIsland/ActivityStore.swift \
  Tests/MacIslandTests/ActivityStoreTests.swift -o "$CHECK_DIR/ActivityStoreChecks"
"$CHECK_DIR/ActivityStoreChecks"
