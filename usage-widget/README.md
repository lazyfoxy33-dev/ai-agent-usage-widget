# Widget Package / 组件包

此目录包含可安装的 Übersicht 组件。完整要求、隐私说明、提供商设置与排错见
[项目 README / project README](../README.md)。

This directory contains the installable Übersicht widget. See the
[project README / 项目 README](../README.md) for requirements, privacy,
provider setup, and troubleshooting.

## 安装 / Install

Recommended installation is through `QuotaWidget.app` > Settings... > Displays. Manual installation remains available for development.

```bash
bash install.sh
```

启动 Übersicht 并在菜单中启用 `usage-widget`。组件每 60 秒运行一次，成功响应
缓存五分钟；接口失败时会显示并标记最后一次成功缓存。需要立即重载时，关闭再
启用该组件。

Start Übersicht and enable `usage-widget` from its menu. The widget runs every
60 seconds; successful responses are cached for five minutes. If an endpoint
fails, the last successful cache remains visible and is marked stale. Disable
and re-enable it for an immediate reload.

Claude 与当前 Kimi Code 凭据可在官方跨进程锁内安全续期并原子写回（旧版 Kimi
凭据保持只读）；Codex 主动探测默认关闭；DeepSeek、SiliconFlow 和 OpenRouter
通过 API key 环境变量显示余额。配置方法见项目 README。

Claude and current Kimi Code credentials refresh under the official
cross-process lock and are written back atomically (legacy Kimi credentials stay
read-only). Codex active probing is disabled by default. DeepSeek, SiliconFlow,
and OpenRouter show balances through API-key environment variables. See the
project README for configuration.

## 测试 / Test

```bash
python3 -m unittest discover -v
```
