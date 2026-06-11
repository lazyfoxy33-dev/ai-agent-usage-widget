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

启动 Übersicht 并在菜单中启用 `usage-widget`。数据每 60 秒自动刷新；需要立即
重载时，关闭再启用该组件。

Start Übersicht and enable `usage-widget` from its menu. Data refreshes every
60 seconds; disable and re-enable it for an immediate reload.

## 测试 / Test

```bash
python3 -m unittest discover -v
```
