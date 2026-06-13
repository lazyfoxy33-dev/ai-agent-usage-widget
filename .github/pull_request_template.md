## Summary / 变更摘要

- Describe the change. / 描述本次改动。

## Verification / 验证

- [ ] `cd core && python3 -m unittest discover -v` (shared data layer / 共享数据层)
- [ ] `cd usage-widget && python3 -m unittest discover -v` (Übersicht widget / 桌面组件)
- [ ] UI changes were checked in Übersicht. / 已在 Übersicht 中检查 UI 改动。
- [ ] Touch Bar changes were checked on a Touch Bar Mac. / Touch Bar 改动已在带触控栏的 Mac 上验证。
- [ ] The diff contains no tokens, sessions, caches, or personal paths. /
      Diff 不包含令牌、会话、缓存或个人路径。
- [ ] User-facing documentation is updated in Chinese and English. /
      用户文档已同步更新中文和英文。

## Provider Safety / 提供商安全

- [ ] Any OAuth refresh runs under the official lock with a post-lock re-read,
      atomic write-back, and a fall-back to expired on failure. /
      任何 OAuth 续期都在官方锁内、锁后重读、原子写回，失败回退过期态。
- [ ] Tokens never appear in process arguments, logs, the repo, or caches. /
      令牌不出现在进程参数、日志、仓库或缓存中。
- [ ] A provider failure does not break other providers. /
      单个提供商失败不会影响其他提供商。
