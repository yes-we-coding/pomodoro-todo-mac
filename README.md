# 番茄待办 · macOS 菜单栏版

🍅 常驻 macOS **菜单栏**的番茄钟 + 待办应用。Apple Silicon 原生（也可构建 Universal）。

复用网页版的前端，套一个轻量原生壳（Swift + SwiftUI + WKWebView），不依赖 Electron。

> 相关版本：
> - 网页/PWA：https://yes-we-coding.github.io/pomodoro-todo-web/
> - Windows 桌面：[pomodoro-todo](https://github.com/yes-we-coding/pomodoro-todo)

## ✨ 特性

- **菜单栏常驻**：顶部状态栏一个 🍅，点开即用，不占 Dock
- **弹窗关闭也持续计时**：WKWebView 常驻内存，番茄结束照常响铃
- **数据持久化**：内置本地回环 HTTP 服务（纯 `Network.framework`），`localStorage` 可靠保存
- **离线可用**：前端资源全部打包进 App
- **完整功能**：番茄钟、待办、标签、重复任务、热力图、高效时段、中断统计、智能总结等

## 🧩 系统要求

- macOS **13 (Ventura)** 或更高
- Apple Silicon（M1/M2/M3/M4）；Intel 也可用 universal 构建
- Xcode（或 Command Line Tools）

## 🛠️ 构建

克隆仓库后，在终端执行：

```bash
cd pomodoro-todo-mac
chmod +x build.sh
./build.sh              # Apple Silicon (arm64)
# 或
./build.sh universal    # arm64 + x86_64
```

脚本会自动：`swift build` → 组装 `.app` → 生成图标 → ad-hoc 签名。

产物在 `dist/PomodoroTodo.app`。

## ▶️ 首次运行

因为是自签名、未公证的 App，第一次需要：

1. 把 `PomodoroTodo.app` 拖进「应用程序」
2. 在 Finder 中 **右键 → 打开** → 弹窗里再点「打开」
3. 菜单栏右上角出现 🍅 即成功

或命令行：

```bash
open dist/PomodoroTodo.app
```

> 若仍提示"无法验证开发者"：系统设置 → 隐私与安全性 → 找到拦截提示 → 点「仍要打开」。

## 🗂️ 项目结构

```
pomodoro-todo-mac
├── Package.swift                 # SwiftPM 定义
├── Info.plist                    # LSUIElement = 菜单栏 App
├── PomodoroTodo.entitlements
├── build.sh                      # 一键构建
├── Sources/PomodoroTodo/
│   └── main.swift                # 本地HTTP服务 + WebView + 菜单栏UI
└── WebRoot/                      # 前端（与网页版一致）
    ├── index.html
    ├── manifest.webmanifest
    ├── sw.js
    └── ...
```

## 🔧 实现说明

| 关注点 | 做法 |
|---|---|
| 菜单栏常驻 | `MenuBarExtra`（`.window` 样式）+ `LSUIElement` + `.accessory` 激活策略 |
| 数据存储 | 本地 `http://127.0.0.1:<随机端口>` 提供静态文件，WKWebView 使用默认持久化 `WKWebsiteDataStore` |
| 后台计时 | WKWebView 由 `AppDelegate` 强持有，弹窗关闭不销毁 |
| 本地服务器 | 基于 `Network.framework`（NWListener），无第三方依赖 |
| 提示音 | Web Audio（已配置允许自动播放） |

## ⚠️ 已知限制（相对 Windows 版）

- 无原生系统级窗口控制（置顶、无边框、迷你窗口）
- 提醒以**响铃 + 菜单图标**为主；如需系统通知，可后续接入 `UNUserNotificationCenter`
- 自签名 App 默认不公证，首次需手动允许

## 📄 License

MIT
