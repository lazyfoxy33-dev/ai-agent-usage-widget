# Claude 刷新+持久化 — 设计文档

> 日期：2026-06-12 · 层：①数据层 · 状态：待实现（交由 Codex）

## 1. 背景 / 为什么反转"只读"

之前 Claude 定为只读，前提是"用户用 Claude Code **CLI**，CLI 会自动刷新 keychain 里的 OAuth token"。**该前提对本用户不成立**：用户用的是 **Claude 桌面 App**（claude.ai 网页会话登录），它**不刷新** keychain 的 `Claude Code-credentials` OAuth token。该 token 每 8 小时过期，没有任何东西刷新它 → widget 的 Claude 面板每 8h 后永久"缓存数据/过期"（实测：token 过期 1.1h，live 返回 `expired`，组件显示 1.2h 前的旧值）。

**结论**：对"只用桌面 App"的用户，只读保不住 Claude 新鲜。且正因为用户不用 CLI，**这条 token 除了 widget 没有别的消费者**，widget 独占续期**零冲突**——当初"只读"防的轮换打架在此不存在。故给 Claude 加"刷新+持久化"。

## 2. 设计：复用 Kimi 已有的并发安全续期协议

完全**镜像 `core/usage/kimi.py`** 已实现并测试过的那套：官方目录锁（`_refresh_lock`：`os.mkdir` 锁 + 心跳 `os.utime` + stale 回收）、**获锁后重读凭证的 peer-轮换短路**（若并发进程已刷新则直接用新的、不重复请求）、form-body 经 stdin 不进 argv、**原子写回**（`os.replace` + 权限收紧），刷新失败回退到 `expired`、不破坏原凭证。

**唯一新增**：Claude 的持久化目标是**平台感知**的，需给 `core/usage/credential_store.py` 加**写**能力（此前只读）：
- macOS：`security add-generic-password -U -a <当前用户> -s "Claude Code-credentials" -w <blob>`
- Windows/Linux：原子写 `~/.claude/.credentials.json`（`CLAUDE_CONFIG_DIR` 可覆盖；临时文件 + `os.replace`；权限仅当前用户）。保留文件其余字段，只更新 token 三项。

## 3. 已验证事实（实测，直接采用）

- 续期端点：`POST https://platform.claude.com/v1/oauth/token`，`Content-Type: application/x-www-form-urlencoded`，body `grant_type=refresh_token&refresh_token=<rt>&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`。返回 `{access_token, refresh_token(轮换), expires_in=28800, ...}`。**body 必须 form-encoded**（JSON 会被网关挡）。
- 凭证结构：`{"claudeAiOauth":{accessToken, refreshToken, expiresAt(毫秒), ...}}`。`expiresAt = int((now + expires_in) * 1000)`。
- 刷新令牌**单次轮换**→ 刷新后**必须立即原子写回**，否则作废登录。
- 出网经本地代理（沿用现有 `_proxy()`）；curl 经 stdin 传密钥不进 argv（沿用现有写法）。
- keychain 写入实测可行；本设计期间已用该流程多次把 Claude 手动续期成功（最近一次 5h 27%/周 43%，有效 +8h）。

## 4. fetch_claude 新流程

读凭证 → 未过期：直接用 → 已过期：获 Claude OAuth 锁 → **重读**（peer 可能已刷新；若已新鲜，释放并用之）→ 仍过期则用 refreshToken 调续期端点 → **原子写回** → 用新 token → 调 `/api/oauth/usage` → parse。续期 401/invalid_grant → `{ok:False, reason:"expired"}`；usage 429 → `rate_limited`（沿用现有）。锁超时/写回失败 → 不破坏原凭证，回退 `expired`/`error`。

## 5. 测试（mock，不触真网络/keychain/文件）

镜像 `core/tests/test_kimi.py` 的续期用例到 Claude：未过期直用 / 过期续期成功并写回 / 获锁后发现 peer 已刷新则不重复请求 / 写回保留未知字段且原子 / 续期 401 → expired / 密钥不进 argv。`credential_store` 加写的平台分支测试（darwin→security mock；win32→临时文件原子写、保留未知字段、权限收紧）。既有 `test_claude.py`/`test_credential_store.py` 全绿。

## 6. 文档

更新 `CONTRIBUTING.md`：把"Claude 凭据必须保持只读"改为"Claude 续期遵循与 Kimi 相同的官方锁+原子写回协议"。`SECURITY.md`/`README` 如有"Claude 永不刷新"措辞一并更新（中英双语）。

## 7. 安全 / 隐私

token 不进 argv、不入日志、不入库；写回只改 token 三项、保留其余；提交身份 noreply、无本机信息（`.githooks/pre-commit` 会拦）。
