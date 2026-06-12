# Übersicht Safe Desktop Position / Übersicht 桌面安全位置

## Goal / 目标

Move the macOS Übersicht widget slightly upward and inward so the Dock does
not cover it, while keeping it below the usual right-side desktop icon column.

将 macOS Übersicht 组件向上、向内移动，避免被程序坞覆盖，同时尽量位于常见的
右侧桌面图标列下方。

## Design / 设计

Use a fixed bottom-right anchor:

使用固定的右下角锚点：

```css
right: 64px;
bottom: 96px;
```

The 96 px bottom margin leaves a practical buffer above a normally sized Dock.
The 64 px right margin moves the widget inward from the desktop icon labels
without pushing it unnecessarily far into the working area.

底部 96 px 为常见尺寸的程序坞保留安全距离；右侧 64 px 让组件避开桌面图标文字
区域，同时不会过多占用桌面中央空间。

The position remains fixed rather than detecting Dock settings dynamically.
This keeps Übersicht behavior predictable when Dock auto-hide, display layout,
or scaling changes.

位置保持固定，不动态探测程序坞设置。这样在程序坞自动隐藏、显示器布局或缩放
发生变化时，组件不会跳动。

## Verification / 验证

- Update the source contract test to require `right: 64px; bottom: 96px;`.
- Assert that the previous `right: 40px; bottom: 40px;` anchor is absent.
- Run the complete `usage-widget` test suite.

- 更新源码契约测试，要求包含 `right: 64px; bottom: 96px;`。
- 断言旧的 `right: 40px; bottom: 40px;` 定位已移除。
- 运行完整的 `usage-widget` 测试套件。
