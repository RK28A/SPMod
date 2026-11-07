#!/bin/bash
set -euo pipefail
version="$1"
out="$2"

work="$(mktemp -d)"
git clone --quiet --depth 1 --branch "$version" https://github.com/apple/swift-protobuf.git "$work/swift-protobuf"

sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
framework="$out/SwiftProtobuf.framework"
modules="$framework/Modules/SwiftProtobuf.swiftmodule"
rm -rf "$framework"
mkdir -p "$modules"

xcrun --sdk iphoneos swiftc \
  -target arm64-apple-ios15.0 \
  -sdk "$sdk" \
  -module-name SwiftProtobuf \
  -parse-as-library \
  -O -whole-module-optimization \
  -enable-library-evolution \
  -emit-library \
  -emit-module \
  -emit-module-path "$modules/arm64-apple-ios.swiftmodule" \
  -emit-module-interface-path "$modules/arm64-apple-ios.swiftinterface" \
  -Xlinker -install_name -Xlinker @rpath/SwiftProtobuf.framework/SwiftProtobuf \
  -o "$framework/SwiftProtobuf" \
  $(find "$work/swift-protobuf/Sources/SwiftProtobuf" -name '*.swift')

cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SwiftProtobuf</string>
  <key>CFBundleIdentifier</key><string>org.swift.protobuf.SwiftProtobuf</string>
  <key>CFBundleName</key><string>SwiftProtobuf</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST

rm -rf "$work"
echo "$framework"
