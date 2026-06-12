# 数据源及时性与准确性 / Data-Source Timeliness & Accuracy

> 日期 / Date: 2026-06-12
> 范围 / Scope: 共享数据层 `core/`

## 目标 / Goal

让 Claude、Codex 和 Kimi 的数据带有统一、可验证的新鲜度信息，同时避免为了
“看起来实时”而破坏官方客户端登录态或暗中消耗用户额度。

Give Claude, Codex, and Kimi a consistent, verifiable freshness contract
without risking official-client login state or silently consuming quota merely
to appear live.

## 审查结论 / Review Findings

原方案中有四项不能直接实施：

1. Claude 和 Kimi 的 refresh token 都可能轮换。“读→刷→写”本身并不具备并发
   安全性；若官方客户端同时刷新，其中一方仍可能拿到 `invalid_grant`。
2. Claude Code 没有公开、可共享的跨进程刷新锁。组件不得自动刷新或写回它的
   Keychain 凭据，继续保持只读。
3. Kimi Code 官方实现提供了明确的刷新锁与原子存储协议，可以安全复用，但必须
   使用同一锁路径、锁后重读和原子替换，不能简单覆盖 JSON。
4. 自动运行 `codex exec` 会产生真实模型请求并消耗额度，必须默认关闭，仅在用户
   显式配置后启用。

Four parts of the original proposal are unsafe as written:

1. Claude and Kimi refresh tokens may rotate. A plain read-refresh-write
   sequence is not concurrency-safe and can still race an official client.
2. Claude Code exposes no public shared refresh lock. The project keeps Claude
   Keychain access read-only and does not refresh its OAuth token.
3. Kimi Code publishes a concrete refresh lock and atomic-storage protocol.
   Reuse is acceptable only with the same lock, a post-lock re-read, and atomic
   replacement.
4. `codex exec` is a real model request. Active probing stays disabled unless
   the user explicitly opts in.

## 已确认事实 / Verified Facts

### Claude

- 用量接口：`https://api.anthropic.com/api/oauth/usage`
- 当前组件只读 `Claude Code-credentials`，不修改 Keychain。
- HTTP 429 是上游限流，不是组件未执行刷新。失败时可以显示旧缓存，但必须标记。
- 不把任何 macOS account 名写死到代码或公开文档。

### Kimi Code

- 用量接口：`https://api.kimi.com/coding/v1/usages`
- OAuth 接口：`https://auth.kimi.com/api/oauth/token`
- 官方 client ID：
  `17e5f671-d194-4dfb-9706-5516cb48c098`
- 当前凭据：
  `${KIMI_CODE_HOME:-$HOME/.kimi-code}/credentials/kimi-code.json`
- 官方刷新目标：
  `${KIMI_CODE_HOME:-$HOME/.kimi-code}/oauth/kimi-code`
- 官方锁目录是上述目标加 `.lock`。刷新临界区内需锁后重读凭据。
- 凭据采用同目录临时文件、`fsync`、`rename` 原子写入，目录权限 `0700`、文件
  权限 `0600`。
- 旧版 `~/.kimi/credentials/kimi-code.json` 继续只读兼容，不主动刷新。

Sources:

- [MoonshotAI/kimi-code OAuth manager](https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/oauth-manager.ts)
- [MoonshotAI/kimi-code token storage](https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/storage.ts)
- [MoonshotAI/kimi-code constants](https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/constants.ts)
- [OpenUsage Kimi provider](https://github.com/robinebers/openusage/blob/main/plugins/kimi/plugin.js)

### Codex

- 限额来自本地 session 的最近一次模型响应，没有独立用量 API。
- 主动探测只能通过真实 `codex exec` 请求获得新响应头，会消耗少量额度。
- 默认只读本地 session。用户显式启用后，才允许按节流规则后台探测。

## 数据契约 / Data Contract

顶层新增：

```json
{
  "schema_version": 1,
  "claude": {},
  "codex": {},
  "kimi": {}
}
```

每个 provider 新增：

- `fetched_at`: `int | null`，该数值对应的数据时间。
- `live`: `bool`，数据是否仍在该 provider 的“可信新鲜窗口”内。
- `reason`: 可选，`expired | error | no_data | stale | rate_limited`。
- `upstream_reason`: 可选，缓存回退时记录导致回退的上游原因。

语义：

- Claude/Kimi 实时请求或五分钟 TTL 内缓存：`live=true`。
- Claude/Kimi 仅能使用过期缓存：`live=false`、`reason=stale`。
- Codex：`fetched_at=as_of`，最近 session 在 30 分钟内则 `live=true`。
- 无数据时 `fetched_at=null`、`live=false`。

`core/CONTRACT.md` 是文字权威说明，`core/contract.schema.json` 描述机器可读形状。
测试使用标准库手写 schema 形状校验，不引入运行时依赖。

## Kimi 安全续期 / Safe Kimi Refresh

仅对当前 `~/.kimi-code` 凭据启用：

1. 发现 token 已过期或用量接口返回 401/403。
2. 获取官方同名锁；等待期间定时检查，超时则返回暂时错误。
3. 获取锁后重新读取凭据。如果其他进程已刷新，直接使用新 token。
4. 使用 form-encoded body 调 OAuth token 接口；refresh token 通过 stdin 发送，
   不进入进程参数。
5. 保留原 JSON 其他字段，更新 token 与过期时间，原子写回。
6. 若刷新返回未授权，短暂等待并重读；若 refresh token 已由其他进程轮换，使用
   新文件自愈，否则返回 `expired`。
7. 始终释放锁。网络错误不破坏原凭据。

Only current `~/.kimi-code` credentials are refreshed. Legacy credentials stay
read-only. The implementation shares the official lock namespace, re-reads
after locking, sends secrets over stdin, preserves unknown fields, and writes
atomically.

## Codex 主动探测 / Active Codex Probe

默认关闭。配置文件：

```text
~/.config/ai-agent-usage-widget/config.json
```

```json
{
  "codex_active_refresh": false,
  "codex_refresh_interval_seconds": 1800
}
```

仅当 `codex_active_refresh=true` 时：

- session 超过阈值且节流锁也超过阈值，才后台运行一次最小请求。
- 启动前原子创建/更新节流记录。
- `stdout`/`stderr` 丢弃，当前取数不等待请求完成。
- 文档明确说明会消耗额度。

## 前端行为 / Frontend Behavior

Übersicht 与 Touch Bar 都必须读取 `live`：

- `live=false` 且仍有数据：显示“较旧/缓存”，颜色降级。
- `fetched_at` 可用于显示数据时间。
- 新字段缺失时保持兼容旧 payload，沿用现有 `reason`/window `stale`。

Both frontends consume `live`; adding fields only in the core while ignoring
them in the UI does not satisfy the accuracy goal.

## 安全 / Security

- 不硬编码用户名、主目录或个人邮箱。
- token 不进入命令行参数、日志、缓存或仓库。
- Claude 凭据保持只读。
- Kimi 仅写回官方凭据文件，并使用官方锁命名与原子写入。
- Codex 主动请求默认关闭。
- 所有相关用户文档保持中英双语。
