#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_CONFIG="${PACKAGE_CONFIG:-$ROOT_DIR/scripts/package.env}"

if [[ -f "$PACKAGE_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$PACKAGE_CONFIG"
fi

APP_NAME="${APP_NAME:-XYLaunch}"
VERSION="${VERSION:-1.0.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_FILE="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
VOLUME_NAME="${VOLUME_NAME:-${APP_NAME} Installer}"

if [[ "${1:-}" == "--help" ]]; then
  cat <<'HELP'
用法:
  ./scripts/create_dmg.sh

可选环境变量:
  APP_NAME=XYLaunch
  VERSION=1.0.0
  VOLUME_NAME="XYLaunch Installer"
  PACKAGE_CONFIG=./scripts/package.env

说明:
  如果 dist/<APP_NAME>.app 不存在，会先调用 package_app.sh 自动打包。
HELP
  exit 0
fi

if [[ ! -d "$APP_DIR" ]]; then
  "$ROOT_DIR/scripts/package_app.sh"
fi

rm -f "$DMG_FILE"

TMP_STAGE="$(mktemp -d /tmp/xylaunch-dmg-stage.XXXXXX)"
trap 'rm -rf "$TMP_STAGE"' EXIT

cp -R "$APP_DIR" "$TMP_STAGE/"
ln -s /Applications "$TMP_STAGE/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$TMP_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_FILE" >/dev/null

echo "已生成 DMG：$DMG_FILE"
