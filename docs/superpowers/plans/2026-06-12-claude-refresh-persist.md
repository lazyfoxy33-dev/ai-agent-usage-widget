# Claude 刷新+持久化 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development 或 executing-plans。
> 配套 spec：`docs/superpowers/specs/2026-06-12-claude-refresh-persist-design.md`。

**Goal:** Claude token 过期时用 refreshToken 续期并原子写回（平台感知：macOS keychain / Win-Linux 文件），让 Claude 长期 live。复用 Kimi 已有的并发安全协议。

**Architecture:** 镜像 `core/usage/kimi.py` 的锁+peer短路+原子写回；给 `credential_store` 加平台感知写；`fetch_claude` 过期分支改为"获锁→重读→续期→写回→取数"。

**Tech Stack:** python3 标准库；`unittest`（`cd core && python3 -m unittest discover`）。测试不触真网络/keychain/文件（mock）。提交身份 noreply（已配）。

> **先验**：续期端点/参数/keychain 写均已实测可行（见 spec §3）。**勿重试**，照做。

---

### Task 1：credential_store 加平台感知写

**Files:** Modify `core/usage/credential_store.py`；Modify `core/tests/test_credential_store.py`

- [ ] 写失败测试：`write_claude_blob(blob, platform=None)`：
  - `platform="darwin"` → 调 `security add-generic-password -U -a <whoami> -s "Claude Code-credentials" -w <blob>`（mock subprocess，断言 argv 含 `add-generic-password` 与 `-U`）；
  - `platform="win32"` → 原子写到 `CLAUDE_CONFIG_DIR/.credentials.json`（临时文件 + `os.replace`），写后内容相等、权限 `0o600`、目录不存在时报错或创建（择一并测）。
- [ ] 实现 `write_claude_blob`：darwin 分支用 `subprocess.run(["security","add-generic-password","-U","-a",getpass.getuser(),"-s",CLAUDE_KEYCHAIN_SERVICE,"-w",blob])`（blob 经参数即可——keychain 写入官方接口如此；若要避免 argv 暴露可改 stdin，但 keychain CLI 不支持 stdin，保持参数，仅本机）；非 darwin 分支：`os.makedirs(dirname, exist_ok=True)`；`tmp=path+".tmp"`；`open(tmp,"w")` 写入；`os.chmod(tmp,0o600)`；`os.replace(tmp,path)`。
- [ ] 跑测试转绿。提交：`feat(core): platform-aware Claude credential write`。

### Task 2：claude.py 续期+持久化（镜像 kimi.py）

**Files:** Modify `core/usage/claude.py`；Modify `core/tests/test_claude.py`

- [ ] 参照 `core/usage/kimi.py` 的 `KimiRefreshUnauthorized`、`_http_refresh`、`_refresh_lock`/`_touch_lock`/`_refresh_lock_target`，在 `claude.py` 加对应的：
  - `ClaudeRefreshUnauthorized(RuntimeError)`；
  - `_http_refresh(refresh_token)`：curl POST `https://platform.claude.com/v1/oauth/token`，form body（`grant_type/refresh_token/client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`），refresh_token 经 stdin/`--data @-` 不进 argv（沿用 kimi 的 stdin 写法）；非 200 → 401/400 抛 `ClaudeRefreshUnauthorized`，其它抛 `RuntimeError`；返回 dict 校验含 `access_token`/`refresh_token`。
  - 续期锁：复用同样的目录锁实现（可把 kimi 的锁三函数提取到 `core/usage/_oauth_lock.py` 共享，或在 claude.py 复制一份；二选一，**优先提取共享**以 DRY）。锁文件名用 Claude 专属 target（如基于 keychain service 名的稳定路径，见 kimi `_refresh_lock_target`）。
- [ ] 写失败测试（镜像 `test_kimi.py` 的续期用例）：未过期直用不刷新；过期→`_http_refresh`（mock 返回新 token）→ `credential_store.write_claude_blob`（mock）被调 → 用新 token 取数；获锁后重读发现 peer 已刷新（mock 第二次读返回未过期）→ 不调 `_http_refresh`；`_http_refresh` 抛 `ClaudeRefreshUnauthorized` → `{ok:False,reason:"expired"}` 且不写回；refresh_token 不在 curl argv。
- [ ] 改 `fetch_claude()`：过期分支 = 获锁 → 重读凭证（peer 短路）→ 仍过期则 `_http_refresh(creds["refreshToken"])` → 合并 `accessToken/refreshToken/expiresAt=int((now+expires_in)*1000)` 进 blob → `credential_store.write_claude_blob(json.dumps(blob))` → 用新 accessToken `_http_get_usage` → `parse_claude_usage`。续期失败→expired；usage 429→`rate_limited`（沿用现有 `ClaudeRateLimitError`）。
- [ ] 跑 `cd core && python3 -m unittest discover -v` 全绿。提交：`feat(core): refresh+persist Claude token via Kimi-style lock protocol`。

### Task 3：文档（双语）

**Files:** Modify `CONTRIBUTING.md`、`SECURITY.md`、`README.md`（如有相关措辞）

- [ ] `CONTRIBUTING.md`：把"Claude 凭据必须保持只读"改为"Claude 续期遵循与当前 Kimi 相同的官方锁 + 锁后重读 + 原子写回协议；失败回退过期态"。中英双语同改。
- [ ] 搜并更新任何"Claude 永不刷新/只读"的过时绝对措辞（`README.md`/`SECURITY.md`/`usage-widget/README.md`）。
- [ ] 提交：`docs: Claude now refreshes under the shared lock protocol`。

### Task 4：真机端到端 + 隐私扫描

- [ ] `cd core && python3 fetch_usage.py`：Claude 过期时应自动续期→`claude.ok=true, live=true`（不再 expired）。token 写回后 keychain `expiresAt` 应为未来 +8h。
- [ ] 扫描 diff 无用户名/home/邮箱/token；`git grep` 同上一轮。提交身份 noreply。
- [ ] 开 PR。

---

## Self-review
- **spec §2 覆盖**：平台感知写→T1；锁+peer短路+原子写回+续期→T2；文档→T3；端到端+隐私→T4。✅
- **DRY**：锁协议优先提取 `_oauth_lock.py` 共享（T2）。
- **安全**：refresh_token 不进 argv；写回只改三项、保留其余；回退不破坏原凭证。✅
