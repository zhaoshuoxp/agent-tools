#!/bin/bash
# Build CodexRadar.app (universal: arm64 + x86_64).
#   ./build.sh            build into ./build/
#   ./build.sh --install  build, copy to ~/Applications and launch
#   ./build.sh --zip      build and create a release zip in ./build/
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
NAME=CodexRadar
OUT=build
APP="$OUT/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" main.swift -o "$OUT/$NAME-$arch" \
    -framework AppKit -framework SwiftUI -framework ServiceManagement
done
lipo -create "$OUT/$NAME-arm64" "$OUT/$NAME-x86_64" -output "$APP/Contents/MacOS/$NAME"
rm -f "$OUT/$NAME-arm64" "$OUT/$NAME-x86_64"

[[ -f icon/AppIcon.icns ]] || { swift icon/make_icon.swift icon && iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns && rm -rf icon/AppIcon.iconset; }
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.zhaoshuoxp.CodexRadar</string>
  <key>CFBundleName</key><string>Codex Radar</string>
  <key>CFBundleDisplayName</key><string>Codex Radar</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP"
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/$NAME"))"

case "${1:-}" in
  --install)
    pkill -x "$NAME" 2>/dev/null || true
    pkill -x ModelRadar 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/"$NAME.app"
    cp -R "$APP" ~/Applications/
    open ~/Applications/"$NAME.app"
    echo "Installed to ~/Applications/$NAME.app"
    ;;
  --zip)
    ZIP="$OUT/$NAME-$VERSION-macOS.zip"
    rm -f "$ZIP"
    ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
    echo "Created $ZIP"
    ;;
esac
