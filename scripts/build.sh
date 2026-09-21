#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
stage=$(mktemp -d /private/tmp/headroom-build.XXXXXX)
trap 'rm -rf "$stage"' EXIT
bundle="$stage/Headroom.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" dist
swift scripts/generate-brand.swift "$stage/brand"
iconutil -c icns "$stage/brand/Headroom.iconset" -o "$bundle/Contents/Resources/Headroom.icns"
bin=$(swift build -c release --show-bin-path)
cp "$bin/Headroom" "$bundle/Contents/MacOS/Headroom"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.headroom.mac</string>
<key>CFBundleName</key><string>Headroom</string>
<key>CFBundleIconFile</key><string>Headroom</string>
<key>CFBundleExecutable</key><string>Headroom</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
ditto -c -k --keepParent --norsrc --noextattr "$bundle" dist/Headroom.zip
ditto --norsrc --noextattr "$bundle" dist/Headroom.app
codesign --verify --strict dist/Headroom.app
printf 'Built %s/dist/Headroom.app\n' "$PWD"
