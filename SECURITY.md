# Security Policy / 安全策略

## 支持版本 / Supported Version

安全修复应用于默认分支上的最新版本。

Security fixes are applied to the latest version on the default branch.

## 报告漏洞 / Reporting A Vulnerability

请使用本仓库的 GitHub 私密漏洞报告功能。不要在公开 Issue 中粘贴凭据、令牌、
会话内容、个人路径或其他敏感信息。

Use GitHub private vulnerability reporting for this repository. Do not put
credentials, tokens, session contents, personal paths, or other sensitive
information in a public issue.

请包含 / Include:

- 问题和影响说明 / Description and impact
- 复现步骤 / Reproduction steps
- 受影响文件或版本 / Affected files or versions
- 可行时提供修复建议 / Suggested fix when available

## 凭据处理 / Credential Handling

本项目必须 / This project must:

- 仅在运行时按需读取提供商凭据。
- Read provider credentials only when required at runtime.
- 不打印、缓存、提交凭据，也不发送给第三方。
- Never print, cache, commit, or transmit credentials to third parties.
- 旧版 Kimi 凭据保持只读。
- Keep legacy Kimi credentials read-only.
- Claude 与当前 Kimi 凭据仅在官方跨进程锁内续期，锁后重读并原子写回。
- Refresh Claude and current Kimi credentials only under the official
  cross-process lock, with a post-lock re-read and atomic replacement.
- 不默认发起 Codex 模型请求。
- Never make Codex model requests by default.
- 不读取浏览器 Cookie 或密码存储。
- Never read browser cookies or password stores.
- 缓存只包含用量百分比与重置时间。
- Keep cache files limited to usage percentages and reset timestamps.

如果令牌意外泄露，请通过对应提供商撤销令牌，并在发布替代版本前从 Git 历史中
彻底移除。

If a token is exposed, revoke it through the provider and remove it from Git
history before publishing a replacement.
