# Widget Package / 组件包

此目录包含可安装的 Übersicht 组件。完整要求、隐私说明、提供商设置与排错见
[项目 README / project README](../README.md)。

This directory contains the installable Übersicht widget. See the
[project README / 项目 README](../README.md) for requirements, privacy,
provider setup, and troubleshooting.

## 安装 / Install

```bash
bash install.sh
```

启动 Übersicht 并在菜单中启用 `usage-widget`。组件每 60 秒运行一次，Claude
和 Kimi 的成功响应缓存五分钟；接口失败时会显示并标记最后一次成功缓存。需要
立即重载时，关闭再启用该组件。

Start Übersicht and enable `usage-widget` from its menu. The widget runs every
60 seconds; successful Claude and Kimi responses are cached for five minutes.
If an endpoint fails, the last successful cache remains visible and is marked
stale. Disable and re-enable it for an immediate reload.

Claude 凭据保持只读。当前 Kimi Code 凭据可在官方跨进程锁内安全续期；Codex
主动探测默认关闭，配置方法见项目 README。

Claude credentials stay read-only. Current Kimi Code credentials may refresh
under the official cross-process lock. Codex active probing is disabled by
default; see the project README for opt-in configuration.

## 测试 / Test

```bash
python3 -m unittest discover -v
```
