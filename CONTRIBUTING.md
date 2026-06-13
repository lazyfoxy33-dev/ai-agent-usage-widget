# Contributing / 贡献指南

欢迎贡献。Contributions are welcome.

## 开始之前 / Before You Start

- 重大行为或 UI 变化请先开 Issue。
- Open an issue before significant behavior or UI changes.
- 保持提供商相互独立，单个失败不得破坏整个组件。
- Keep providers independent so one failure cannot break the whole widget.
- 旧版 Kimi 凭据保持只读；Claude 与当前 Kimi 续期必须复用官方锁、锁后重读
  和原子写回协议，续期失败回退到过期态。
- Legacy Kimi credentials stay read-only. Claude and current Kimi refresh must
  reuse the official lock, post-lock re-read, and atomic write-back protocol,
  falling back to the expired state on failure.
- 其他 OAuth 续期只有在存在可共享的并发协议且轮换后的令牌能原子写回时才允许；
  失败必须回退到过期态。
- Other OAuth refresh is allowed only with a shared concurrency protocol and
  atomic persistence of rotated tokens; failures must fall back to expired.
- 任何主动模型请求必须默认关闭，并要求用户显式选择。
- Any active model request must be disabled by default and require explicit
  user opt-in.
- 不得提交真实凭据、Keychain 导出、会话、缓存或机器专属路径。
- Never commit real credentials, Keychain exports, sessions, caches, or
  machine-specific paths.

## 开发环境 / Development Setup

```bash
git clone https://github.com/lazyfoxy33-dev/ai-agent-usage-widget.git
cd ai-agent-usage-widget/core
python3 -m unittest discover -v   # 数据层测试 / data-layer tests
python3 fetch_usage.py
```

前端验证命令 / Frontend verification commands:

```bash
# Übersicht
cd usage-widget && python3 -m unittest discover -v

# Touch Bar
cd touchbar
python3 -m unittest discover -v
./build.sh

# macOS WidgetKit（无需签名的本地验证 / unsigned local verification）
cd macwidget
xcodebuild test -project QuotaWidget.xcodeproj -scheme QuotaWidget \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
QUOTAWIDGET_UNSIGNED=1 ./build.sh

# Windows Tauri（在 Windows 上运行 / run on Windows）
cd windows-widget
node --test src/render.test.mjs
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo test --manifest-path src-tauri/Cargo.toml
cargo build --release --manifest-path src-tauri/Cargo.toml
```

macOS App Group 签名流程必须使用有效 Apple Team 验证；Windows 安装包、托盘与
开机自启必须在 Windows 10/11 上验证。

Validate the signed macOS App Group flow with a real Apple Team. Validate the
Windows installer, tray, and autostart behavior on Windows 10/11.

`fetch_usage.py` 会读取本机提供商状态。分享输出前请检查并清理隐私信息。

`fetch_usage.py` reads local provider state. Inspect and sanitize its output
before sharing it.

## 隐私强制 / Privacy Enforcement

仓库为公开仓库。**任何提交都不得泄露本机或个人信息**（用户名、home 绝对路径、个人邮箱、账号/设备 id、令牌、个人用量数字）。

This repo is public. **No commit may leak machine-local or personal info.**

- 提交身份用 GitHub noreply 邮箱（非个人邮箱）。Commit identity uses the GitHub noreply email.
- 路径用 `~`/`$HOME`，用户名用 `$USER`。Use `~`/`$HOME` and `$USER`, never literal values.
- 仓库内 `.githooks/pre-commit` 会机械拦截违规提交。克隆后激活一次：
  A `.githooks/pre-commit` hook enforces this. Activate once per clone:

  ```bash
  git config core.hooksPath .githooks
  ```

  AI agent 另见根目录 `AGENTS.md`。AI agents: see `AGENTS.md`.

## Pull Request

1. 数据层改动必须添加或更新测试。
2. Add or update tests for data-layer changes.
3. 运行相关完整测试套件，并在对应平台检查 UI 改动。
4. Run the relevant full test suite and inspect UI changes on the target platform.
5. 说明提供商/API 假设，保持改动聚焦。
6. Explain provider/API assumptions and keep the change focused.
7. 确认 diff 不包含令牌、个人路径、会话或缓存。
8. Confirm the diff contains no tokens, personal paths, sessions, or caches.
9. 涉及用户文档时，同时更新中文和英文。
10. Update both Chinese and English when changing user-facing documentation.

## 代码风格 / Code Style

- Python 数据层仅使用标准库。Python data code uses the standard library only.
- 分离解析、缓存、编排和渲染职责。Keep parsing, caching, orchestration, and
  rendering responsibilities separate.
- 明确显示失败状态，不把旧数据伪装为实时数据。Prefer explicit failure states
  over silently presenting outdated data.
- 只配置一个提供商时组件仍应可用。Keep the widget usable with any single
  provider configured.
