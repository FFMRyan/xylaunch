# XYLaunch

macOS 状态栏启动台应用（SwiftUI）。

## 运行

```bash
cd /Users/ys/Desktop/XYLaunch
swift run
```

## Xcode 运行

已包含可直接打开的工程：

- `/Users/ys/Desktop/XYLaunch/XYLaunch.xcodeproj`

步骤：

1. 双击 `XYLaunch.xcodeproj`（或 `open XYLaunch.xcodeproj`）
2. 选择 Scheme `XYLaunch`
3. 点击 Xcode 顶部 `Run`

说明：Xcode 调试运行时默认显示 Dock 图标，便于确认应用已启动。

如果首次使用 Xcode 命令行工具，请先在终端同意许可协议：

```bash
sudo xcodebuild -license accept
```

## 打包 .app

```bash
cd /Users/ys/Desktop/XYLaunch
./scripts/package_app.sh
```

产物：

- `dist/XYLaunch.app`

### 自定义品牌信息

先复制配置模板：

```bash
cp scripts/package.env.example scripts/package.env
```

可配置字段：

- `APP_NAME`：应用显示名
- `EXECUTABLE_NAME`：可执行文件名（默认 `XYLaunch`）
- `BUNDLE_ID`：Bundle Identifier
- `VERSION`：版本号（如 `1.2.3`）
- `BUILD_NUMBER`：构建号（纯数字）
- `ICON_SOURCE`：品牌图标文件路径（支持 `.icns/.png/.jpg/.jpeg`）

也可以直接临时传参：

```bash
APP_NAME="MyLauncher" \
BUNDLE_ID="com.yourcompany.mylauncher" \
VERSION="1.0.0" \
BUILD_NUMBER="3" \
ICON_SOURCE="./assets/brand-icon.png" \
./scripts/package_app.sh
```

## 生成 DMG

```bash
cd /Users/ys/Desktop/XYLaunch
./scripts/create_dmg.sh
```

产物：

- `dist/XYLaunch-<VERSION>.dmg`
