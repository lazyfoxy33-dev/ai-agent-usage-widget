# 数据源及时性与准确性实现计划 / Implementation Plan

> 配套设计 / Design:
> `docs/superpowers/specs/2026-06-12-data-source-timeliness-accuracy-design.md`

**Goal:** Add an honest freshness contract, safely refresh current Kimi Code
credentials, and make Codex active probing explicit opt-in.

**Architecture:** Keep Claude credentials read-only. Extend the shared core
contract first, then add Kimi refresh under the official cross-process lock and
atomic storage protocol. Add optional Codex probing through a user config file.
Update both frontends and bilingual documentation in the same change.

**Tech Stack:** Python 3 standard library, Übersicht JSX, Swift/AppKit,
`unittest`

---

## Task 1：契约与缓存时间 / Contract And Cache Timestamps

**Files:**

- Create: `core/CONTRACT.md`
- Create: `core/contract.schema.json`
- Create: `core/tests/test_contract.py`
- Modify: `core/usage/cache.py`
- Modify: `core/tests/test_cache.py`
- Modify: `core/fetch_usage.py`
- Modify: `core/tests/test_fetch.py`

1. 先写失败测试：
   - cache 能返回 `{ts,data}`；
   - payload 有 `schema_version=1`；
   - 每个 provider 始终有 `fetched_at` 和 `live`；
   - 旧缓存回退为 `live=false/reason=stale` 并保留上游原因。
2. 实现 `cache.read_entry()` / `read_stale_entry()`，保留旧 API 兼容。
3. 实现统一结果归一化，不改变既有百分比字段。
4. 写双语契约与 JSON Schema；标准库测试直接校验实际 payload 形状。
5. 跑 `python3 -m unittest discover -v`。

## Task 2：Claude 限流状态 / Claude Rate-Limit State

**Files:**

- Modify: `core/usage/claude.py`
- Modify: `core/tests/test_claude.py`

1. 先写失败测试：HTTP 429 映射为 `reason=rate_limited`，令牌过期仍为
   `reason=expired`。
2. 增加明确异常类型，不刷新、不写 Keychain。
3. 让缓存层把实时失败原因放入 `upstream_reason`。

## Task 3：Kimi 官方锁与原子存储 / Kimi Official Lock And Storage

**Files:**

- Modify: `core/usage/kimi.py`
- Modify: `core/tests/test_kimi.py`

1. 先写失败测试：
   - client ID 与 OAuth endpoint 正确；
   - secrets 不进入 curl argv；
   - 当前凭据过期会刷新；
   - 获取锁后发现 peer 已刷新时不重复请求；
   - 写回保留未知字段、权限 `0600`、使用 `os.replace`；
   - legacy 凭据保持只读；
   - 401 后只刷新并重试一次。
2. 实现官方锁命名、等待、heartbeat 和锁后重读。
3. 用 form body stdin 调 refresh endpoint。
4. 原子持久化，再调用 usage；失败不破坏原文件。

## Task 4：Codex 显式 opt-in 探测 / Explicit Opt-In Probe

**Files:**

- Create: `core/usage/config.py`
- Create: `core/tests/test_config.py`
- Modify: `core/usage/codex.py`
- Modify: `core/tests/test_codex.py`
- Modify: `core/fetch_usage.py`

1. 先写失败测试：配置缺失/无效时默认关闭。
2. 解析 `~/.config/ai-agent-usage-widget/config.json`。
3. 仅在显式开启、session 超阈值、节流记录超阈值时 `Popen`。
4. 写测试证明默认路径永不发模型请求。

## Task 5：两个前端消费新鲜度 / Frontend Freshness

**Files:**

- Modify: `usage-widget/index.jsx`
- Modify: `usage-widget/tests/test_widget_source.py`
- Modify: `touchbar/Sources/DataSource.swift`
- Modify: `touchbar/Sources/TouchBarController.swift`

1. 先写/更新测试，约束 `live=false` 显示缓存状态。
2. Swift 解码 `fetched_at/live`，缺失时兼容旧 payload。
3. Übersicht 使用 `live` 和 `reason` 统一降级显示。
4. 构建 Touch Bar，安装并目视检查 Übersicht。

## Task 6：文档、隐私与发布验证 / Docs, Privacy, Release

**Files:**

- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `SECURITY.md`
- Modify: `usage-widget/README.md`
- Modify: `touchbar/README.md`
- Modify: `touchbar/install.sh`

1. 中英双语说明 Claude 只读、Kimi 安全续期、Codex opt-in 的额度影响。
2. 删除“所有 token 永不刷新”的过时绝对描述。
3. 运行：

```bash
cd core && python3 -m unittest discover -v
cd ../usage-widget && python3 -m unittest discover -v
cd ../touchbar && ./build.sh
```

4. 安装 Übersicht 组件并核对真实输出。
5. 扫描个人路径、邮箱、token、私钥和提交身份。
6. 更新 PR，等待/执行合并。
