# Speakin 踩坑记录

记录重大 bug 的根因分析与修复过程，便于复盘和防止重蹈覆辙。

---

## INC-001 — 键盘劫持（macOS 26 beta，NSEvent.mouseLocation 主线程限制）

**日期**：2026-04-12
**版本**：v0.4.0 → v0.4.1
**严重程度**：高（键盘完全卡死，需强杀进程）

### 症状

用户反馈在 macOS 26 beta 上，使用 Speakin 后整个系统键盘输入被劫持——按任意键均无响应，只能通过 `pkill Speakin` 恢复。

### 根因

定位过程：

1. 查看 `~/Library/Logs/Speakin/app.log`，发现即使没有任何按键操作，日志也在疯狂刷新 `[Hotkey] tap re-enabled`。
2. `tapDisabledByTimeout` 事件触发说明 CGEvent 回调执行时间超过了 macOS 规定的 **250ms** 阈值，系统强制 disable 了 tap。
3. 追溯回调代码，发现三处热键触发路径（Fn、修饰键、keyDown）均在 CGEvent 回调中直接调用了 `Self.mousePositionRect()`：

```swift
// 问题代码（在后台线程执行的 CGEvent 回调中）
let mouseRect = Self.mousePositionRect()  // ← NSEvent.mouseLocation，macOS 26 在此阻塞！
DispatchQueue.main.async { [weak self] in
    self?.lastCaretRect = Self.captureCaretRect() ?? mouseRect
    self?.delegate?.hotkeyDidPress()
}
```

4. `NSEvent.mouseLocation` 在 macOS 26 beta 中被强化为 **MainActor isolation**，在后台线程（CGEvent 回调所在线程）中调用会阻塞等待主线程调度，造成回调超时。

### 修复

将所有 `mousePositionRect()` 调用移入 `DispatchQueue.main.async`，确保 CGEvent 回调本身不调用任何 AppKit API：

```swift
// 修复后（CGEvent 回调中不再调用任何 AppKit API）
DispatchQueue.main.async { [weak self] in
    guard let self = self else { return }
    self.lastCaretRect = Self.captureCaretRect() ?? Self.mousePositionRect()
    self.delegate?.hotkeyDidPress()
}
```

修复涉及 `HotkeyMonitor.swift` 三个方法：`handleFlagsChangedForFn`、`handleFlagsChangedForCustomModifier`、`handleKeyDown`。

### 经验教训

**CGEvent 回调是后台线程，绝对禁止调用 AppKit API。** 具体规则见本文末尾"CGEvent 回调安全规则"。

---

## INC-002 — 键盘劫持（tap disable 后 hotkeyPressed 状态卡死）

**日期**：2026-04-12（与 INC-001 同期排查时发现的历史隐患）
**版本**：v0.4.0（引入，此前 FnKeyMonitor 也有相同问题）
**严重程度**：中（概率性发生，热键卡住后按住触发键可自愈）

### 症状

系统睡眠/唤醒、或 tap 因其他原因被 disable 后，所有键盘输入均被吞掉，直到再次按住触发键。

### 根因

tap 被系统 disable 时，若热键恰好处于按住状态（`hotkeyPressed = true`），则 re-enable 后：

- keyDown 热键：tap 会 suppress 所有匹配按键，包括用户不知情时的普通打字
- Fn/修饰键热键：suppress 逻辑依赖 `hotkeyPressed` 状态，若状态不对则行为异常

旧版 `reEnableIfNeeded()` 直接 re-enable tap，未同步实际硬件状态：

```swift
// 问题代码
func reEnableIfNeeded() {
    if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
        CGEvent.tapEnable(tap: tap, enable: true)  // ← 未同步 hotkeyPressed！
    }
}
```

### 修复

re-enable 前调用 `syncHardwareState()`，从 `CGEventSource.flagsState` 读取实际硬件修饰键状态，将 `hotkeyPressed` 同步到真实值：

```swift
func reEnableIfNeeded() {
    if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
        syncHardwareState()  // 先同步，再 enable
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private func syncHardwareState() {
    if let hotkey = registeredHotkey {
        if hotkey.isModifierOnly {
            let currentFlags = CGEventSource.flagsState(.combinedSessionState)
            hotkeyPressed = currentFlags.contains(hotkey.modifierFlags)
        } else {
            hotkeyPressed = false  // keyDown 状态无法从 flagsState 获取，默认未按住
        }
    } else {
        hotkeyPressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
    }
}
```

### 经验教训

**CGEvent tap 每次 re-enable 前，必须先将内部状态与硬件实际状态同步。** tap 被 disable 期间发生的按键事件是"黑洞"，内部状态可能与实际完全不符。

---

## CGEvent 回调安全规则

CGEvent tap 的回调运行在**后台线程**（非主线程）。以下规则必须严格遵守：

| 规则 | 说明 |
|------|------|
| 禁止调用任何 AppKit / UIKit API | `NSEvent.*`、`NSScreen.*`、`NSApplication.*` 等均不允许 |
| 禁止执行耗时操作 | 文件 I/O、网络、锁竞争均不允许，目标执行时间 **< 1ms** |
| 禁止阻塞等待主线程 | 回调超过 250ms macOS 会强制 disable tap，产生键盘劫持 |
| 需要主线程资源时 | 用 `DispatchQueue.main.async` 异步派发，回调本身立即返回 |
| 修饰键事件永远不 suppress | 系统必须看到修饰键状态变化，否则影响全局输入法/快捷键 |
| 可安全使用 | `event.flags`、`event.getIntegerValueField()`、`CGEventSource.flagsState()` |

---

*本文件记录对系统级稳定性有重大影响的 bug，普通功能 bug 记录在 CHANGELOG.md。*
