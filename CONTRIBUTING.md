# Contributing / 贡献指南

欢迎贡献。Contributions are welcome.

## 开始之前 / Before You Start

- 重大行为或 UI 变化请先开 Issue。
- Open an issue before significant behavior or UI changes.
- 保持提供商相互独立，单个失败不得破坏整个组件。
- Keep providers independent so one failure cannot break the whole widget.
- 不得新增 OAuth 刷新行为；所有提供商凭据必须保持只读。
- Do not add OAuth refresh behavior; provider credentials must remain read-only.
- 不得提交真实凭据、Keychain 导出、会话、缓存或机器专属路径。
- Never commit real credentials, Keychain exports, sessions, caches, or
  machine-specific paths.

## 开发环境 / Development Setup

```bash
git clone https://github.com/lazyfoxy33-dev/ai-agent-usage-widget.git
cd ai-agent-usage-widget/usage-widget
python3 -m unittest discover -v
python3 fetch_usage.py
```

`fetch_usage.py` 会读取本机提供商状态。分享输出前请检查并清理隐私信息。

`fetch_usage.py` reads local provider state. Inspect and sanitize its output
before sharing it.

## Pull Request

1. 数据层改动必须添加或更新测试。
2. Add or update tests for data-layer changes.
3. 运行完整测试套件，并在 Übersicht 中检查 UI 改动。
4. Run the full test suite and check UI changes in Übersicht.
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
