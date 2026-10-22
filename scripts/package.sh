#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh --universal
STAGE=$(mktemp -d /tmp/mac-island-dmg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
ditto 'dist/Mac Island.app' "$STAGE/Mac Island.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -ov -volname 'Mac Island' -srcfolder "$STAGE" -format UDZO 'dist/Mac-Island.dmg'
ditto -c -k --sequesterRsrc --keepParent 'dist/Mac Island.app' 'dist/Mac-Island.zip'
(cd dist && shasum -a 256 Mac-Island.dmg Mac-Island.zip > SHA256SUMS.txt)
