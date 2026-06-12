# 组件 1：数据层跨平台移植 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development 或 executing-plans。步骤用 `- [ ]` 跟踪。
> 配套 spec：`docs/superpowers/specs/2026-06-12-native-frontends-mac-windows-design.md` §3。

**Goal:** 让 `core/` 在 Windows/Linux 也能取到 Claude 用量（凭证从文件读，而非 macOS Keychain），Claude 保持只读。

**Architecture:** 新增 `core/usage/credential_store.py` 做平台感知的 Claude 凭证**读取**；`claude.py` 转调它。Codex/Kimi 本就文件凭证，跨平台基本现成，仅需 Windows 实测。

**Tech Stack:** python3 标准库；`unittest`（`cd core && python3 -m unittest discover`）。

测试**不触**真 keychain/文件/网络（mock）。提交身份 noreply（仓库已配），结尾不放个人信息（`.githooks/pre-commit` 会拦）。

---

### Task 1：credential_store 平台感知读取

**Files:**
- Create: `core/usage/credential_store.py`
- Test: `core/tests/test_credential_store.py`

- [ ] **Step 1: 写失败测试**

```python
# core/tests/test_credential_store.py
import os, tempfile, unittest
from unittest import mock
from usage import credential_store as cs


class TestReadClaudeBlob(unittest.TestCase):
    def test_darwin_uses_security(self):
        fake = mock.Mock(stdout='{"claudeAiOauth":{"accessToken":"a"}}\n')
        with mock.patch("usage.credential_store.subprocess.run", return_value=fake) as run:
            blob = cs.read_claude_blob(platform="darwin")
        self.assertIn("accessToken", blob)
        args = run.call_args[0][0]
        self.assertEqual(args[0], "security")

    def test_non_darwin_reads_file(self):
        d = tempfile.mkdtemp()
        p = os.path.join(d, ".credentials.json")
        with open(p, "w") as f:
            f.write('{"claudeAiOauth":{"accessToken":"x"}}')
        with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": d}):
            blob = cs.read_claude_blob(platform="win32")
        self.assertIn('"accessToken":"x"', blob)

    def test_missing_returns_none(self):
        with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": "/no/such/dir"}):
            self.assertIsNone(cs.read_claude_blob(platform="linux"))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd core && python3 -m unittest tests.test_credential_store -v`
Expected: FAIL（`ModuleNotFoundError: usage.credential_store`）

- [ ] **Step 3: 实现 credential_store.py**

```python
# core/usage/credential_store.py
"""Platform-aware, read-only credential source for Claude.

darwin -> macOS Keychain (`security`); otherwise a file
(~/.claude/.credentials.json, overridable via CLAUDE_CONFIG_DIR).
Claude credentials are READ-ONLY here; there is no write-back.
"""
import os
import subprocess
import sys

CLAUDE_KEYCHAIN_SERVICE = "Claude Code-credentials"


def _claude_file_path():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude"
    return os.path.join(os.path.expanduser(base), ".credentials.json")


def read_claude_blob(platform=None):
    """Return raw Claude credential JSON string, or None."""
    plat = platform if platform is not None else sys.platform
    if plat == "darwin":
        try:
            out = subprocess.run(
                ["security", "find-generic-password",
                 "-s", CLAUDE_KEYCHAIN_SERVICE, "-w"],
                capture_output=True, text=True, timeout=10,
            )
            return out.stdout.strip() or None
        except (OSError, subprocess.SubprocessError):
            return None
    try:
        with open(_claude_file_path()) as f:
            return f.read().strip() or None
    except OSError:
        return None
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd core && python3 -m unittest tests.test_credential_store -v`
Expected: 3 PASS

- [ ] **Step 5: 提交**

```bash
git add core/usage/credential_store.py core/tests/test_credential_store.py
git commit -m "feat(core): platform-aware read-only Claude credential source"
```

---

### Task 2：claude.py 转调 credential_store

**Files:**
- Modify: `core/usage/claude.py`（`read_keychain_blob` 改为委托；删除内联 `security` 调用）
- Test: `core/tests/test_claude.py`（既有，需保持绿）

- [ ] **Step 1: 改 `read_keychain_blob` 为委托**

把 `core/usage/claude.py` 中 `read_keychain_blob()` 的函数体替换为：

```python
def read_keychain_blob():
    """Return raw Claude credential JSON (platform-aware), or None."""
    from usage import credential_store
    return credential_store.read_claude_blob()
```

并删除该函数原来直接调用 `subprocess.run(["security", ...])` 的代码（已搬入 credential_store）。`KEYCHAIN_SERVICE` 常量若仅此处用到可一并移除；若别处引用则保留。`fetch_claude`/其余逻辑**不动**（仍只读）。

- [ ] **Step 2: 跑既有 claude 测试确认仍绿**

Run: `cd core && python3 -m unittest tests.test_claude -v`
Expected: 全 PASS（外部行为未变；若有测试 mock 了 `claude.subprocess.run`，改为 mock `credential_store` 或 `claude.read_keychain_blob`）。

- [ ] **Step 3: 全量回归**

Run: `cd core && python3 -m unittest discover -v`
Expected: 全绿（应为既有 69 + 新增 3 ≈ 72）

- [ ] **Step 4: 提交**

```bash
git add core/usage/claude.py core/tests/test_claude.py
git commit -m "refactor(core): claude reads via credential_store"
```

---

### Task 3：Windows/Linux 可执行定位 + 实测核验（需 Windows 机/用户协助）

**Files:**
- Modify: `core/usage/codex.py`、`core/usage/kimi.py`（仅在硬编码可执行路径处）

- [ ] **Step 1: 可执行定位用 `shutil.which`**

检查 `codex.py`/`kimi.py` 中定位 `codex`/`kimi` 可执行的代码：若硬编码 `~/.local/bin/codex` 之类，改为 `shutil.which("codex") or shutil.which("codex.exe") or <原回退>`（Windows 可执行带 `.exe`）。`os.path.expanduser` 与 `os.path.join` 已跨平台，路径分隔符无需手拼。若已用 `shutil.which`，本步跳过。

- [ ] **Step 2: 增 Windows 路径单测（不触真文件）**

在 `core/tests/test_codex.py`/`test_kimi.py` 增一条：monkeypatch `shutil.which` 返回 `C:\\...\\codex.exe`，断言定位逻辑返回它（mock 文件/子进程）。

- [ ] **Step 3: 提交**

```bash
git add core/usage/codex.py core/usage/kimi.py core/tests/
git commit -m "feat(core): locate provider CLIs cross-platform via which"
```

- [ ] **Step 4: 真机核验（人工，非 CI）**

在一台 Windows（已装 Claude Code / Codex / Kimi 并登录）上：
1. 确认 `%USERPROFILE%\.claude\.credentials.json` 为 `{"claudeAiOauth":{...}}`；`~/.codex`、`~/.kimi-code` 目录与文件同 macOS。
2. 装 python3，`cd core && python -m unittest discover` 全绿。
3. `python fetch_usage.py` 能出三家 JSON（Claude 至少能读到 token 状态；Codex/Kimi 同）。必要时设 `HTTPS_PROXY`。
4. 把发现（任何结构差异）回填到 spec §8 并据此修代码 + 加测试。

---

## Self-review
- **Spec §3 覆盖**：read 平台感知→T1；claude 转调→T2；Codex/Kimi 跨平台+实测→T3。✅
- **Claude 只读**：无写回任务（符合决定）。✅
- **Placeholder**：T3 实测为人工核验步骤，含具体核对项，非空泛占位。✅
