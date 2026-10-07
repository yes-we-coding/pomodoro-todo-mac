#!/bin/bash
# 构建 macOS 菜单栏 App（Apple Silicon / Universal 可选）
# 用法：
#   ./build.sh              # arm64（Apple Silicon）
#   ./build.sh universal    # arm64 + x86_64
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
CONFIG="release"
ARCH_ARG=""
NAME_IN_DIST="PomodoroTodo"

if [[ "${1:-}" == "universal" ]]; then
  ARCH_ARG="--arch arm64 --arch x86_64"
  echo "==> 构建 Universal（arm64 + x86_64）"
else
  ARCH_ARG="--arch arm64"
  echo "==> 构建 arm64（Apple Silicon）"
fi

APP="dist/$NAME_IN_DIST.app"

echo "==> 1/5 swift build"
swift build -c $CONFIG $ARCH_ARG

BIN="$(swift build -c $CONFIG $ARCH_ARG --show-bin-path)/PomodoroTodo"
echo "    可执行文件: $BIN"

echo "==> 2/5 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/WebRoot"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/PomodoroTodo"
cp -R WebRoot/. "$APP/Contents/Resources/WebRoot/"

echo "==> 3/5 生成 App 图标"
ICONSET="dist/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
SRC="WebRoot/icon-512.png"
sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png"       >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png"       >/dev/null
sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png"     >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png"     >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png"     >/dev/null
cp "$SRC" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# 在 Info.plist 中引用图标
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true

echo "==> 4/5 代码签名（ad-hoc，本机可运行）"
codesign --force --deep --sign - \
  --options runtime \
  --entitlements PomodoroTodo.entitlements \
  "$APP"

echo "==> 5/5 完成"
echo ""
echo "✅ 已生成: $ROOT/$APP"
echo ""
echo "首次运行（因为是未公证的自签名 App）："
echo "  1) 把 PomodoroTodo.app 拖到「应用程序」文件夹"
echo "  2) 在 Finder 里右键 → 打开 → 再点「打开」"
echo "  3) 菜单栏右上角出现 🍅 即成功"
echo ""
echo "或直接命令行打开： open \"$APP\""
