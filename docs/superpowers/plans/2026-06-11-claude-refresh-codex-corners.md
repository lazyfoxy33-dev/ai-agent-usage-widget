# Claude Refresh And Codex Corners Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document Claude's effective refresh behavior and give the Codex icon Apple-style continuous corners.

**Architecture:** Keep the five-minute provider cache because the live Claude endpoint is currently rate-limiting requests. Keep stale fallback unchanged. Apply clipping directly to the existing Codex image element and document the effective behavior bilingually.

**Tech Stack:** Python 3 standard library, Übersicht JSX, `unittest`, Markdown

---

### Task 1: Refresh Policy Regression / 刷新策略回归

**Files:**
- Modify: `usage-widget/tests/test_fetch.py`
- Modify: `usage-widget/fetch_usage.py`

- [ ] **Step 1: Write a failing test / 编写失败测试**

```python
def test_provider_success_cache_is_five_minutes(self):
    with mock.patch.object(fetch_usage.cache, "read", return_value={"ok": True}) as read:
        fetch_usage.claude_with_cache()
        read.assert_called_once_with(
            fetch_usage.CACHE_PATH,
            ttl=fetch_usage.CACHE_TTL,
        )

    self.assertEqual(fetch_usage.CACHE_TTL, 300)
```

- [ ] **Step 2: Verify red / 验证红灯**

Run:

```bash
cd usage-widget
python3 -m unittest tests.test_fetch.TestFetch.test_provider_success_cache_is_five_minutes -v
```

Expected: pass against the retained five-minute policy.

- [ ] **Step 3: Implement / 实现**

Keep `CACHE_TTL = 300` and add the regression test so future changes account
for endpoint rate limiting before increasing request frequency.

- [ ] **Step 4: Verify green / 验证绿灯**

Run the focused test and `tests.test_fetch`.

### Task 2: Codex Continuous Corners / Codex 连续圆角

**Files:**
- Modify: `usage-widget/tests/test_widget_source.py`
- Modify: `usage-widget/index.jsx`

- [ ] **Step 1: Write a failing test / 编写失败测试**

```python
def test_codex_icon_uses_apple_style_continuous_corners(self):
    self.assertIn('borderRadius: 8', self.source)
    self.assertIn('overflow: "hidden"', self.source)
    self.assertIn(
        'WebkitMaskImage: "-webkit-radial-gradient(white, black)"',
        self.source,
    )
```

- [ ] **Step 2: Verify red / 验证红灯**

Run the focused widget-source test. Expected: failure on the missing styles.

- [ ] **Step 3: Implement / 实现**

Add the three clipping styles to the existing 27×27 Codex image without
changing its asset or layout.

- [ ] **Step 4: Verify green / 验证绿灯**

Run the focused test and all widget-source tests.

### Task 3: Documentation And Release Verification / 文档与发布验证

**Files:**
- Modify: `README.md`
- Modify: `usage-widget/README.md`

- [ ] **Step 1: Update both languages / 更新中英文**

State that the command runs every 60 seconds, successful provider responses
cache for five minutes, and stale fallback may keep the last successful Claude
value visible during failures or rate limiting.

- [ ] **Step 2: Run full verification / 完整验证**

```bash
cd usage-widget
python3 -m unittest discover -v
bash -n install.sh
python3 fetch_usage.py | python3 -m json.tool >/dev/null
bash install.sh
```

- [ ] **Step 3: Inspect Übersicht / 检查 Übersicht**

Confirm the Codex icon is rounded and both provider values still render.

- [ ] **Step 4: Commit and push / 提交并推送**

Commit using the repository's GitHub noreply identity and push `main`.
