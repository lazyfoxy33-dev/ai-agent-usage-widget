## Summary / 变更摘要

- Describe the change. / 描述本次改动。

## Verification / 验证

- [ ] `cd usage-widget && python3 -m unittest discover -v`
- [ ] UI changes were checked in Übersicht. / 已在 Übersicht 中检查 UI 改动。
- [ ] The diff contains no tokens, sessions, caches, or personal paths. /
      Diff 不包含令牌、会话、缓存或个人路径。
- [ ] User-facing documentation is updated in Chinese and English. /
      用户文档已同步更新中文和英文。

## Provider Safety / 提供商安全

- [ ] Credentials remain read-only. / 凭据保持只读。
- [ ] No OAuth refresh or token persistence was added. /
      未新增 OAuth 刷新或令牌持久化。
- [ ] A provider failure does not break other providers. /
      单个提供商失败不会影响其他提供商。
