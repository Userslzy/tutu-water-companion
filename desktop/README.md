# macOS 桌面版开发说明

使用 AppKit 的透明悬浮 NSPanel 与保留在内存中的 WKWebView。关闭主窗口会收回桌面兔兔；原生计时器和 JSON 存储在主窗口关闭后继续工作。页面及图片全部内置，本地消息通信只接受应用内主页面，不加载线上网站，也不读取浏览器记录。

## 构建与打包

需要 macOS、Python 3 与 Apple Command Line Tools（Swift 5.7 及以上）。无需第三方包。

```sh
# 当前 Mac 架构
python3 desktop/build.py
# Apple 芯片 + Intel 通用应用
python3 desktop/build.py --universal
# 通用 ZIP，附使用说明和 SHA-256
python3 desktop/package.py
```

应用输出：`desktop/output/兔兔喝水.app`。发布文件输出：`desktop/output/releases/`。构建脚本完成本地 ad-hoc 签名和签名完整性检查；未进行 Developer ID 签名及 Apple 公证。打包采用 Apple 的 `ditto` 保留应用目录与可执行文件权限。

通用包包含 arm64 和 x86_64 两个架构，最低系统为 macOS 13。目前实际运行验证环境为 Apple 芯片 Mac，Intel 架构仅完成编译与签名检查。

## 验证

```sh
xcrun swiftc desktop/Sources/State.swift desktop/Sources/ReminderMotion.swift desktop/tests/main.swift -o /tmp/tutu-model-tests
/tmp/tutu-model-tests
./desktop/output/兔兔喝水.app/Contents/MacOS/TutuWater --self-test
```

客户端自检使用独立临时数据目录，并在完成后退出。检查悬浮窗口、页面收回、无需通知权限的到点动画、点击展开不自动记录、关闭后继续提醒、恢复过期状态、延后、暂停、撤销、实际页面按钮与原生存储通信。截图输出至 `desktop/output/qa/`。

## 发布说明

发布版本记录见 [CHANGELOG.md](../CHANGELOG.md)。GitHub Releases 应附上版本 ZIP 和 `SHA256SUMS.txt`，将安装步骤及未公证状态放在发行说明中。

## 数据和系统设置

数据位于 `~/Library/Application Support/TutuWater/water-state.json`。构建和打包不读取使用者的喝水记录。应用仅在使用者主动开启通知时请求通知权限；不会自动设置开机启动。原生后台活动允许电脑正常休眠，唤醒后检查提醒时间。
