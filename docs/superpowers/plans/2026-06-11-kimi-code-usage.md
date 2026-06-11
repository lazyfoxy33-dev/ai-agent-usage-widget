# Kimi Code Usage Implementation Plan / Kimi Code 用量实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **给执行者：** 必须按任务逐项执行，推荐使用
> `superpowers:subagent-driven-development`，也可使用
> `superpowers:executing-plans`。所有步骤使用复选框跟踪。

**Goal / 目标：** Add an independent Kimi Code five-hour/weekly usage panel,
replace the clipped Codex glyph with the complete app icon, and make all
affected user-facing documentation bilingual.

新增独立的 Kimi Code 五小时/每周用量面板，使用完整的 Codex App 图标替换被裁切
的自绘图标，并将本次涉及的用户文档改为中英双语。

**Architecture / 架构：** A new stdlib-only `usage.kimi` provider reads the
current or legacy Kimi OAuth file and calls the same `/coding/v1/usages`
endpoint as Kimi Code CLI. `fetch_usage.py` owns five-minute caching and stale
fallback. `index.jsx` renders the third provider using local brand assets
copied by `install.sh`.

新增仅使用 Python 标准库的 `usage.kimi` 模块，读取 Kimi CLI OAuth 文件并调用
CLI 同源的 `/coding/v1/usages` 接口。`fetch_usage.py` 负责五分钟缓存和过期数据
兜底，`index.jsx` 使用由 `install.sh` 安装的本地品牌图片渲染第三块面板。

**Tech Stack / 技术栈：** Python 3 standard library, `curl`, Übersicht JSX,
`unittest`, shell installer, PNG assets.

---

### Task 1: Kimi Provider / Kimi 数据模块

**Files:**
- Create: `usage-widget/usage/kimi.py`
- Create: `usage-widget/tests/test_kimi.py`
- Create: `usage-widget/tests/fixtures/kimi_usage.json`

- [ ] **Step 1: Write failing credential and parsing tests / 编写凭据和解析失败测试**

Tests must establish:

```python
def test_credentials_path_honors_kimi_code_home(self):
    with mock.patch.dict(os.environ, {"KIMI_CODE_HOME": "/tmp/kimi-code"}):
        self.assertEqual(
            kimi.credentials_path(),
            "/tmp/kimi-code/credentials/kimi-code.json",
        )

def test_parse_usage_maps_five_hour_and_weekly(self):
    result = kimi.parse_kimi_usage(self.fixture)
    self.assertEqual(result["five_h"]["pct"], 34)
    self.assertEqual(result["weekly"]["pct"], 8)
```

Also cover token expiry, `used` versus `remaining`, percentage clamping,
300-minute window selection, and Unix/ISO/protobuf-style reset timestamps.

- [ ] **Step 2: Verify RED / 验证红灯**

Run:

```bash
cd usage-widget
python3 -m unittest tests.test_kimi -v
```

Expected: import failure because `usage.kimi` does not exist.

- [ ] **Step 3: Implement credentials and parser / 实现凭据与解析**

Implement these public functions:

```python
def credential_paths():
    current = os.environ.get("KIMI_CODE_HOME") or os.path.expanduser("~/.kimi-code")
    legacy = os.environ.get("KIMI_SHARE_DIR") or os.path.expanduser("~/.kimi")
    return [
        os.path.join(current, "credentials", "kimi-code.json"),
        os.path.join(legacy, "credentials", "kimi-code.json"),
    ]

def read_credentials(path=None):
    ...

def is_expired(credentials, now=None):
    ...

def parse_kimi_usage(payload):
    ...
```

Return the common provider shape:

```python
{
    "ok": True,
    "five_h": {"pct": 34, "resets_at": 1781190000},
    "weekly": {"pct": 8, "resets_at": 1781600000},
}
```

- [ ] **Step 4: Add failing HTTP token-safety test / 添加 HTTP 令牌安全失败测试**

Patch `subprocess.run`, call `_http_get_usage("secret-token")`, and assert the
token is absent from every command argument but present in the stdin curl
configuration.

- [ ] **Step 5: Verify RED / 验证红灯**

Run the single HTTP test. Expected: failure because `_http_get_usage` is
missing.

- [ ] **Step 6: Implement safe HTTP fetch and provider pipeline / 实现安全请求与提供商流程**

Use:

```text
curl -q --config - -sS --max-time 20
GET https://api.kimi.com/coding/v1/usages
```

Pass `Authorization: Bearer ...` only through stdin. Map missing credentials to
`no_data`, expired or HTTP 401/403 credentials to `expired`, and other failures
to `error`. Never refresh the token.

- [ ] **Step 7: Verify GREEN / 验证绿灯**

Run:

```bash
python3 -m unittest tests.test_kimi -v
python3 -m unittest discover -v
```

- [ ] **Step 8: Commit / 提交**

```bash
git add usage-widget/usage/kimi.py usage-widget/tests/test_kimi.py \
  usage-widget/tests/fixtures/kimi_usage.json
git commit -m "Add Kimi Code usage provider"
```

### Task 2: Payload And Cache / 组合数据与缓存

**Files:**
- Modify: `usage-widget/fetch_usage.py`
- Modify: `usage-widget/tests/test_fetch.py`

- [ ] **Step 1: Write failing orchestration tests / 编写组合与缓存失败测试**

Add tests that require:

```python
self.assertEqual(out["kimi"]["five_h"]["pct"], 34)
```

and verify a successful Kimi result is cached while a later transient error
returns stale cached data with `reason == "stale"`.

- [ ] **Step 2: Verify RED / 验证红灯**

Run `python3 -m unittest tests.test_fetch -v`. Expected: missing Kimi payload or
helper.

- [ ] **Step 3: Implement Kimi cache orchestration / 实现 Kimi 缓存编排**

Add:

```python
KIMI_CACHE_PATH = os.path.expanduser("~/.cache/usage-widget/kimi.json")

def kimi_with_cache():
    ...
```

Import `usage.kimi`, keep Claude and Kimi cache files separate, and include all
three providers in `build_payload()`.

- [ ] **Step 4: Verify GREEN and commit / 验证绿灯并提交**

```bash
python3 -m unittest tests.test_fetch -v
python3 -m unittest discover -v
git add usage-widget/fetch_usage.py usage-widget/tests/test_fetch.py
git commit -m "Cache and combine Kimi usage"
```

### Task 3: Brand Assets And Installer / 品牌图片与安装脚本

**Files:**
- Create: `usage-widget/assets/kimi-code.png`
- Create: `usage-widget/assets/codex-app.png`
- Create: `usage-widget/tests/test_install.py`
- Modify: `usage-widget/install.sh`

- [ ] **Step 1: Write failing installer test / 编写安装脚本失败测试**

Assert `install.sh` copies `assets` into `$DEST/assets` and both expected PNG
filenames exist in the source tree.

- [ ] **Step 2: Verify RED / 验证红灯**

Run `python3 -m unittest tests.test_install -v`. Expected: missing assets and
copy command.

- [ ] **Step 3: Add official assets / 添加官方图片**

Use:

- Kimi: `MoonshotAI/kimi-code/docs/.vitepress/theme/Kimi.png`
- Codex: complete cloud icon from
  `/Applications/Codex.app/Contents/Resources/app.icns`

Export compact PNGs with transparency retained. Do not edit the logo shapes.

- [ ] **Step 4: Update installer / 更新安装脚本**

Add:

```bash
rm -rf "$DEST/assets"
cp -R "$SRC/assets" "$DEST/"
```

- [ ] **Step 5: Verify GREEN and commit / 验证绿灯并提交**

```bash
python3 -m unittest tests.test_install -v
bash -n install.sh
git add usage-widget/assets usage-widget/install.sh usage-widget/tests/test_install.py
git commit -m "Package provider brand assets"
```

### Task 4: Three-Panel Renderer / 三面板渲染

**Files:**
- Modify: `usage-widget/index.jsx`
- Modify: `usage-widget/tests/test_widget_source.py`

- [ ] **Step 1: Write failing renderer tests / 编写渲染失败测试**

Require:

```python
self.assertIn('const KM = { accent: "#1478FF"', self.source)
self.assertIn('src="./assets/kimi-code.png"', self.source)
self.assertIn('src="./assets/codex-app.png"', self.source)
self.assertIn('data.kimi', self.source)
self.assertNotIn('aria-label="codex-cloud"', self.source)
```

Also retain the bottom-right position and smaller three-digit percentage test.

- [ ] **Step 2: Verify RED / 验证红灯**

Run `python3 -m unittest tests.test_widget_source -v`. Expected: missing Kimi
panel and image assets.

- [ ] **Step 3: Implement renderer / 实现渲染**

Add the chosen A palette:

```javascript
const KM = {
  accent: "#1478FF",
  soft: "#252A33",
  ink: "#17181C",
  sub: "#737984",
  track: "rgba(20,24,30,.09)"
};
```

Render Kimi below Codex with the shared ring and row layout. Replace the
hand-drawn Codex SVG with a 27-pixel image containing inset space. Add
provider-specific empty-state messages for Kimi login, expiry, and stale data.

- [ ] **Step 4: Verify GREEN and commit / 验证绿灯并提交**

```bash
python3 -m unittest tests.test_widget_source -v
python3 -m unittest discover -v
git add usage-widget/index.jsx usage-widget/tests/test_widget_source.py
git commit -m "Render Kimi usage and complete Codex icon"
```

### Task 5: Bilingual Documentation / 双语文档

**Files:**
- Modify: `README.md`
- Modify: `usage-widget/README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `SECURITY.md`
- Modify: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Modify: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Modify: `.github/pull_request_template.md`
- Modify: `docs/superpowers/specs/2026-06-11-kimi-code-usage-design.md`

- [ ] **Step 1: Convert affected docs to paired Chinese and English / 将相关文档改为中英对照**

Every heading and user instruction must be understandable in both languages.
Document Kimi installation/login, the official endpoint, cache behavior,
manual console link, no-cookie/no-refresh policy, and error states. Add Kimi to
the issue template provider list and update “both providers” wording to “other
providers”.

- [ ] **Step 2: Add trademark attribution / 添加商标归属**

State in both languages that the project is unofficial and that Claude, Codex,
Kimi, OpenAI, Anthropic, Moonshot AI, and their logos are trademarks or brand
assets of their respective owners.

- [ ] **Step 3: Validate links and language coverage / 验证链接与双语覆盖**

Run a local Markdown link checker script using Python standard library and
manually scan the changed docs for English-only user-facing sections.

- [ ] **Step 4: Commit / 提交**

```bash
git add README.md usage-widget/README.md CONTRIBUTING.md SECURITY.md .github \
  docs/superpowers/specs/2026-06-11-kimi-code-usage-design.md \
  docs/superpowers/plans/2026-06-11-kimi-code-usage.md
git commit -m "Document Kimi support in Chinese and English"
```

### Task 6: Integration Verification And Release / 集成验证与发布

**Files:**
- Modify only if verification exposes a defect.

- [ ] **Step 1: Run full verification / 运行完整验证**

```bash
cd usage-widget
python3 -m unittest discover -v
bash -n install.sh
python3 fetch_usage.py | python3 -m json.tool >/dev/null
```

- [ ] **Step 2: Run privacy scan / 运行隐私扫描**

Scan tracked files for personal paths, personal email addresses, access tokens,
private keys, and accidentally committed credential/session data.

- [ ] **Step 3: Install and verify local widget / 安装并验证本机组件**

Run `bash install.sh`, compare installed source/assets against the repository,
and confirm the installed payload remains valid JSON.

- [ ] **Step 4: Visual verification / 视觉验证**

Reload Übersicht and verify:

- Three panels render independently.
- Kimi uses visual direction A.
- Codex cloud icon is complete and not clipped.
- The widget remains anchored 40 pixels from the right and bottom.

- [ ] **Step 5: Merge and push / 合并并推送**

After fresh verification, merge the feature branch into `main` and push only
`main` to the existing public repository.
