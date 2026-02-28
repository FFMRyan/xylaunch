# XYLaunch

macOS 状态栏启动台应用（SwiftUI）。

## 运行

```bash
cd /Users/ys/Desktop/XYLaunch
swift run
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
