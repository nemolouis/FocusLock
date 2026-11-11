#!/bin/bash
# 构建 FocusLock.app（只需要 Xcode Command Line Tools，不需要完整 Xcode）
# 用法: ./build.sh          构建到 build/FocusLock.app
#       ./build.sh install  构建并复制到 /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="FocusLock"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
mkdir -p "$BUILD"

EXTRA_FLAGS=()
# 部分机器上的 Command Line Tools 残留了一个 2023 年的 module.modulemap，
# 会和新的 bridging.modulemap 冲突（redefinition of module 'SwiftBridging'）。
# 用 VFS overlay 把它屏蔽掉，不改动系统文件。
CLT_INC="$(dirname "$(dirname "$(xcrun -f swiftc)")")/include/swift"
if [[ -f "$CLT_INC/module.modulemap" && -f "$CLT_INC/bridging.modulemap" ]]; then
  : > "$BUILD/empty.modulemap"
  cat > "$BUILD/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "name": "$CLT_INC", "type": "directory",
  "contents": [ { "name": "module.modulemap", "type": "file", "external-contents": "$PWD/$BUILD/empty.modulemap" } ] } ] }
EOF
  EXTRA_FLAGS+=(-vfsoverlay "$PWD/$BUILD/overlay.yaml")
fi

ARCH="$(uname -m)"
echo "▸ 编译 ($ARCH)…"
swiftc \
  -O -swift-version 5 \
  -target "$ARCH-apple-macosx14.0" \
  -module-name FocusLock \
  -module-cache-path "$BUILD/ModuleCache" \
  ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
  Sources/FocusLock/*.swift \
  -o "$BUILD/FocusLock"

echo "▸ 打包 $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/FocusLock" "$APP/Contents/MacOS/FocusLock"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f "$BUILD/AppIcon.icns" ]]; then
  echo "▸ 生成图标…"
  swiftc ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} -module-cache-path "$BUILD/ModuleCache" \
    scripts/make_icon.swift -o "$BUILD/make_icon"
  rm -rf "$BUILD/AppIcon.iconset"
  "$BUILD/make_icon" "$BUILD/AppIcon.iconset"
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
fi
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "✓ 完成: $PWD/$APP"

if [[ "${1:-}" == "install" ]]; then
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  echo "✓ 已安装到 /Applications/$APP_NAME.app"
fi
