#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp/}mac-island-timer.XXXXXX")
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -parse-as-library Sources/MacIsland/CountdownTimer.swift \
  Tests/MacIslandTests/CountdownTimerTests.swift -o "$CHECK_DIR/CountdownTimerChecks"
"$CHECK_DIR/CountdownTimerChecks"
