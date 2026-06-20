# Windows Tauri Widget / Windows Tauri 桌面组件

This frontend is a transparent, frameless Tauri window for Windows. It stays on
top, can be dragged from the status bar, remembers its position, refreshes
every 60 seconds, and provides show/hide, refresh, autostart, and quit actions
from the system tray.

此前端是 Windows 上的透明无边框 Tauri 窗口。它可置顶、可从状态栏拖动、会记住
位置、每 60 秒刷新，并在系统托盘提供显示/隐藏、刷新、开机自启和退出操作。

## Requirements / 要求

- Windows 10 or 11 with WebView2 / 带 WebView2 的 Windows 10 或 11
- Python 3 available as `python`, `python3`, or `py -3`
- Python 3 可通过 `python`、`python3` 或 `py -3` 启动
- Rust stable and Tauri CLI for source builds
- 从源码构建需要 Rust stable 与 Tauri CLI
- At least one supported official CLI has been used and signed in
- 至少登录并使用过一个受支持的官方 CLI

## Build And Install / 构建与安装

Open PowerShell in this directory and run:

在此目录打开 PowerShell 并运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build.ps1
```

The script runs Rust tests and creates an MSI/NSIS installer under
`src-tauri\target\release\bundle\`.

脚本会先运行 Rust 测试，再在 `src-tauri\target\release\bundle\` 下生成
MSI/NSIS 安装包。

For development / 开发运行：

```powershell
cargo install tauri-cli --version "^2"
cd src-tauri
cargo tauri dev
```

Frontend tests use Node's built-in test runner and do not require npm:

前端测试使用 Node 内置测试 runner，不依赖 npm：

```powershell
node --test ..\src\render.test.mjs
```

## Use / 使用

- Drag the top status bar to move the widget. Its position is restored on the
  next launch.
- 拖动顶部状态栏移动组件；下次启动会恢复位置。
- Click the refresh icon or choose **立即刷新** from the tray.
- 点击刷新图标，或从托盘选择**立即刷新**。
- The app enables autostart on first launch. Toggle it from the tray menu.
- app 首次启动会开启开机自启，可在托盘菜单中切换。
- A failed refresh leaves the last successful data visible and changes only
  the status message.
- 刷新失败时保留上一次成功数据，只更新状态提示。

## 分发 / Distribution

构建并生成安装包：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build.ps1
```

构建完成后，安装包位于 `src-tauri\target\release\bundle\`（MSI 和 NSIS 两种格式）。

The installer is built under `src-tauri\target\release\bundle\` (MSI and NSIS).

发布到 GitHub Release：

```powershell
.\release.ps1
```

可选参数 / Options:
- `-Tag "v1.0.0"` — 指定 Release tag（默认自动推断为 `windows-widget-v{version}`）
  Specify the release tag (defaults to `windows-widget-v{version}`)
- `-NoPublish` — 只构建不上传
  Build only, skip upload

跨平台发布（从 macOS/Linux 调用）/ Cross-platform release from macOS/Linux:

```bash
cd ..
./release.sh --windows
```

## Credentials And Privacy / 凭据与隐私

The bundled `core/` reads official local stores. On Windows, Claude uses
`~/.claude/.credentials.json`; an expired token is refreshed under the official
lock and written back atomically (the file is rewritten with `os.replace`).
Tokens are sent to provider APIs through curl config stdin and are never placed
in process arguments or logs.

内置的 `core/` 读取官方本地存储。Windows 上 Claude 读取
`~/.claude/.credentials.json`；令牌过期时在官方锁内续期并原子写回（用
`os.replace` 重写该文件）。令牌通过 curl config 标准输入发送到提供商 API，
不进入进程参数或日志。

## Troubleshooting / 排错

- **Python not detected:** verify `python --version` or `py -3 --version` works
  in a new PowerShell window.
- **未检测到 Python：**在新的 PowerShell 窗口确认 `python --version` 或
  `py -3 --version` 可用。
- **One provider is empty:** run `python ..\core\fetch_usage.py` from the
  repository root and follow that provider's login message.
- **单个提供商为空：**在仓库根目录运行 `python .\core\fetch_usage.py`，按对应
  提供商的登录提示处理。
- Proxy variables `HTTPS_PROXY` and `https_proxy` are honored.
- 支持 `HTTPS_PROXY` 与 `https_proxy` 代理环境变量。
