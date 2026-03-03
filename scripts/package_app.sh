#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
TMP_DIR="$DIST_DIR/.tmp"
PACKAGE_CONFIG="${PACKAGE_CONFIG:-$ROOT_DIR/scripts/package.env}"

if [[ -f "$PACKAGE_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$PACKAGE_CONFIG"
fi

APP_NAME="${APP_NAME:-小火箭启动器}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-XYLaunch}"
BUNDLE_ID="${BUNDLE_ID:-com.xylaunch.app}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ICON_SOURCE="${ICON_SOURCE:-$ROOT_DIR/Xcode/Resources/appicon.png}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
SKIP_CODESIGN="${SKIP_CODESIGN:-0}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-13.0}"
LS_UI_ELEMENT="${LS_UI_ELEMENT:-0}"
USE_XCODEBUILD="${USE_XCODEBUILD:-1}"
XCODE_SCHEME="${XCODE_SCHEME:-XYLaunch}"
XCODE_PROJECT="${XCODE_PROJECT:-$ROOT_DIR/XYLaunch.xcodeproj}"
XCODE_CONFIGURATION="${XCODE_CONFIGURATION:-Release}"
XCODE_PRODUCT_NAME="${XCODE_PRODUCT_NAME:-XYLaunch}"

APP_DIR="$DIST_DIR/${APP_NAME}.app"
ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
BASE_ICON_PNG="$TMP_DIR/AppIconBase.png"
ICNS_FILE="$TMP_DIR/AppIcon.icns"

mkdir -p "$DIST_DIR" "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ "${1:-}" == "--help" ]]; then
  cat <<'HELP'
用法:
  ./scripts/package_app.sh

可选环境变量:
  APP_NAME=小火箭启动器
  EXECUTABLE_NAME=XYLaunch
  BUNDLE_ID=com.xylaunch.app
  VERSION=1.0.0
  BUILD_NUMBER=1
  ICON_SOURCE=./assets/brand-icon.png   # 支持 .png/.jpg/.jpeg/.icns
  CODESIGN_IDENTITY=-                    # 默认 ad-hoc
  SKIP_CODESIGN=1                        # 跳过签名
  MIN_SYSTEM_VERSION=13.0
  LS_UI_ELEMENT=0                         # 1=状态栏模式，0=常规应用
  USE_XCODEBUILD=1                        # 优先使用 xcodebuild 产物
  XCODE_SCHEME=XYLaunch
  XCODE_PROJECT=./XYLaunch.xcodeproj
  XCODE_CONFIGURATION=Release
  XCODE_PRODUCT_NAME=XYLaunch
  PACKAGE_CONFIG=./scripts/package.env
HELP
  exit 0
fi

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "VERSION 格式无效: $VERSION（示例: 1.2.3）" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER 必须是数字: $BUILD_NUMBER" >&2
  exit 1
fi

if [[ -n "$ICON_SOURCE" && "$ICON_SOURCE" != /* ]]; then
  ICON_SOURCE="$ROOT_DIR/$ICON_SOURCE"
fi

create_icns_from_png() {
  local source_png="$1"
  local iconset_dir="$2"
  local output_icns="$3"

  rm -rf "$iconset_dir"
  mkdir -p "$iconset_dir"

  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    local double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$source_png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$iconset_dir" -o "$output_icns"
}

generate_default_icon_png() {
  local output_png="$1"
  local monogram="$2"

  swift - "$output_png" "$monogram" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count > 2 else {
    fatalError("Missing arguments")
}

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let monogram = CommandLine.arguments[2]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
NSColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1).setFill()
canvas.fill()

let card = NSRect(x: 72, y: 72, width: 880, height: 880)
let cardPath = NSBezierPath(roundedRect: card, xRadius: 220, yRadius: 220)
let gradient = NSGradient(
    colors: [
        NSColor(red: 0.15, green: 0.54, blue: 0.98, alpha: 1),
        NSColor(red: 0.06, green: 0.72, blue: 0.86, alpha: 1),
    ]
)
gradient?.draw(in: cardPath, angle: 35)

let overlayRect = NSRect(x: 120, y: 120, width: 784, height: 784)
let overlayPath = NSBezierPath(roundedRect: overlayRect, xRadius: 170, yRadius: 170)
NSColor.white.withAlphaComponent(0.14).setFill()
overlayPath.fill()

let text = monogram as NSString
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 320, weight: .black),
    .foregroundColor: NSColor.white,
]
let textSize = text.size(withAttributes: attributes)
let textRect = NSRect(
    x: (size.width - textSize.width) / 2,
    y: (size.height - textSize.height) / 2 + 10,
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect, withAttributes: attributes)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Failed to create PNG")
}

try png.write(to: outURL, options: .atomic)
SWIFT
}

resolve_icon_icns() {
  if [[ -n "$ICON_SOURCE" ]]; then
    if [[ ! -f "$ICON_SOURCE" ]]; then
      echo "ICON_SOURCE 文件不存在: $ICON_SOURCE" >&2
      exit 1
    fi

    local lower_path
    lower_path="$(echo "$ICON_SOURCE" | tr '[:upper:]' '[:lower:]')"

    if [[ "$lower_path" == *.icns ]]; then
      cp "$ICON_SOURCE" "$ICNS_FILE"
      return
    fi

    if [[ "$lower_path" == *.png || "$lower_path" == *.jpg || "$lower_path" == *.jpeg ]]; then
      cp "$ICON_SOURCE" "$BASE_ICON_PNG"
      create_icns_from_png "$BASE_ICON_PNG" "$ICONSET_DIR" "$ICNS_FILE"
      return
    fi

    echo "ICON_SOURCE 仅支持 .icns/.png/.jpg/.jpeg: $ICON_SOURCE" >&2
    exit 1
  fi

  local monogram
  monogram="$(printf '%s' "$APP_NAME" | tr -cd '[:alnum:]' | cut -c1-2 | tr '[:lower:]' '[:upper:]')"
  if [[ -z "$monogram" ]]; then
    monogram="XY"
  fi

  generate_default_icon_png "$BASE_ICON_PNG" "$monogram"
  create_icns_from_png "$BASE_ICON_PNG" "$ICONSET_DIR" "$ICNS_FILE"
}

pushd "$ROOT_DIR" >/dev/null
if [[ "$USE_XCODEBUILD" == "1" && -d "$XCODE_PROJECT" ]]; then
  XCODE_DERIVED_DATA="$ROOT_DIR/.xcodebuild-package"
  xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$XCODE_SCHEME" \
    -configuration "$XCODE_CONFIGURATION" \
    -derivedDataPath "$XCODE_DERIVED_DATA" \
    build >/dev/null
  EXECUTABLE_PATH="$XCODE_DERIVED_DATA/Build/Products/$XCODE_CONFIGURATION/$XCODE_PRODUCT_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"
else
  BIN_DIR="$(swift build -c release --show-bin-path)"
  swift build -c release
  EXECUTABLE_PATH="$BIN_DIR/$EXECUTABLE_NAME"
fi
popd >/dev/null

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "无法找到可执行文件: $EXECUTABLE_PATH" >&2
  exit 1
fi

resolve_icon_icns

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ICNS_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_SYSTEM_VERSION}</string>
  <key>LSUIElement</key>
  <$([[ "$LS_UI_ELEMENT" == "1" ]] && echo "true" || echo "false")/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "$SKIP_CODESIGN" != "1" ]]; then
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR" >/dev/null
fi

echo "已生成应用：$APP_DIR"
