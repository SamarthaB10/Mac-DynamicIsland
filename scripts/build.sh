#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p core/target/link dist
APP="dist/Mac Island.app"
mkdir -p "$APP/Contents/MacOS"
if [[ "${1:-}" == "--universal" ]]; then
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release --target "$target" --manifest-path core/Cargo.toml
  done
  lipo -create core/target/aarch64-apple-darwin/release/libisland_core.a core/target/x86_64-apple-darwin/release/libisland_core.a -output core/target/link/libisland_core.a
  touch Sources/IslandCore/bridge.c
  for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx14.0"
    BIN_DIR=$(swift build -c release --triple "$arch-apple-macosx14.0" --show-bin-path)
    cp "$BIN_DIR/MacIsland" "dist/MacIsland-$arch"
  done
  lipo -create dist/MacIsland-arm64 dist/MacIsland-x86_64 -output "$APP/Contents/MacOS/MacIsland"
else
  MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release --manifest-path core/Cargo.toml
  cp core/target/release/libisland_core.a core/target/link/libisland_core.a
  # Rebuilding the C bridge makes SwiftPM re-link Rust-only changes.
  touch Sources/IslandCore/bridge.c
  swift build -c release
  BIN_DIR=$(swift build -c release --show-bin-path)
  cp "$BIN_DIR/MacIsland" "$APP/Contents/MacOS/MacIsland"
fi
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --entitlements scripts/MacIsland.entitlements "$APP"
echo "Built $APP"
