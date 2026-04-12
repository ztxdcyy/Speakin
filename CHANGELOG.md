# Changelog

All notable changes to Speakin will be documented in this file.

## [v0.4.1] - 2026-04-12

### Fixed

- **修复键盘劫持问题（macOS 26 beta）**
  - 在 macOS 26 beta 中，`NSEvent.mouseLocation` 强化了主线程要求，在 CGEvent 回调（后台线程）中直接调用会导致阻塞
  - 阻塞超过 250ms 后 macOS 强制 disable CGEvent tap，期间键盘事件无法正常流转，产生键盘劫持体验
  - 修复：将所有 `mousePositionRect()` 调用移入 `DispatchQueue.main.async`，CGEvent 回调本身不再调用任何 AppKit API，执行时间 < 1ms

---

## [v0.4.0] - 2026-04-12

### Added

- **用户自定义触发热键 — 支持外接键盘**
  - 设置窗口新增「触发按键」区域，可录制任意自定义热键
  - 支持三种热键类型：
    - Fn 键（默认，仅内置键盘）
    - 纯修饰键（如右 Option、右 Command）—— 通过 `flagsChanged` 检测，不拦截系统事件
    - 功能键（如 F13–F19）或修饰键组合 —— 通过 `keyDown`/`keyUp` 检测，精确拦截
  - 「重置」按钮可随时恢复 Fn 默认
  - 热键切换实时生效，无需重启应用
  - 验证逻辑：拒绝 Cmd+字母等系统保留组合，拒绝无修饰的普通按键

### Technical

- 新增 `HotkeyMonitor`（替换 `FnKeyMonitor`）：支持动态 eventMask、录制模式暂停/恢复
- 新增 `UserHotkeyConfig`：`Codable` 数据模型，持久化到 UserDefaults（JSON 编码）
- `SettingsWindowController` 窗口高度 220→310pt，新增热键录制状态机
- 录制期间 disable CGEventTap，通过 `NSEvent.addLocalMonitorForEvents` 捕获按键，不影响其他应用
- `reEnableIfNeeded()` 在 tap 重启前同步硬件状态，防止修饰键卡死

---

## [v0.3.0] - 2026-04-08

### Changed

- **Menu bar icon: vectorized bird logo via potrace**
  - Replaced the old menu bar icon with a potrace-vectorized SVG derived from the app logo (`minilogo.jpg`).
  - SVG uses pure white paths on transparent background, set as a template image — automatically adapts to macOS light/dark mode.
  - Icon logical size set to 30×30pt for better visibility.

- **Capsule floating bird icon: high-res with transparent background**
  - Replaced the old low-res (20×20) opaque capsule bird icon with a high-resolution version sourced from `logo_bird.png` (1024×1024).
  - White background removed (alpha transparency) using Python/Pillow.
  - Now renders at 60×60pt (120×120 @2x) for crisp, clear display next to the recording capsule.

### Technical

- Added `potrace` to the toolchain for PNG→SVG vectorization.
- Updated `Makefile` to copy `bird_menubar.svg` into app bundle (both `build` and `release` targets).
- Added `bird_menubar.svg` to `Package.swift` exclude list to suppress SPM warning.
- `MenuBarManager.loadMenuBarImage()` now loads SVG instead of PNG.
- `CapsulePanel.birdSize` increased from 24pt to 60pt; `birdGap` from 4 to 6.

---

## [v0.2.0] - 2026-04-02

### Changed

- **Switched ASR engine from Qwen-Omni-Realtime to Paraformer-Realtime-v2**
  - Dedicated streaming ASR model via DashScope `/api-ws/v1/inference` endpoint.
  - Semantic punctuation enabled for smarter sentence boundary detection.
  - Accumulates final sentences for complete transcription.

- **Compact capsule design**
  - Capsule resized to 72×32 pill shape with 5-bar waveform animation.
  - Floating bird icon displayed outside the capsule during recording.
  - Error text shown inline with auto-dismiss after 2 seconds.

---

## [v0.1.1] - 2026-04-02

### Fixed

- **Transcription accuracy: model no longer "answers" questions instead of transcribing**
  - Previously, the Qwen-Omni-Realtime model would sometimes interpret spoken input as a question or command and reply conversationally rather than transcribing verbatim.
  - Switched from `response.create`-based transcription to DashScope's dedicated `input_audio_transcription` feature (`gummy-realtime-v1` model), which is purpose-built for pure STT.
  - `turn_detection` is now set to `null` (manual mode) — no auto-VAD triggering unwanted responses.
  - Fn key release now only commits the audio buffer; no `response.create` is sent.
  - Listens for `conversation.item.input_audio_transcription.completed` event for the final transcript.
  - Removed all `response.text.delta` / `response.done` handling (no longer needed).

- **Transcription prompt hardened to prevent conversational replies** *(included in this release)*
  - Changed session modalities from `[text, audio]` to `[text]` only — disables voice reply mode entirely.
  - Rewrote system instructions to explicitly forbid answering questions or following commands; model is instructed to output verbatim transcription only.

### Changed

- `RealtimeAPIClient`: removed `response.create` call on commit; simplified event handling loop.
- `RealtimeModels`: added `InputAudioTranscriptionConfig` and `TranscriptionCompletedEvent` Codable models.
- `SessionCoordinator`: updated to handle `transcriptionCompleted` delegate callback instead of `responseTextDone`.

---

## [v0.1.0] - 2026-04-01

### Added

- Initial release of Speakin — macOS menu bar app for voice-to-text via Fn key.
- Fn key hold-to-record with 300 ms anti-bounce and 15 s response timeout.
- Audio streaming via WebSocket to Alibaba DashScope Qwen-Omni-Realtime API (16 kHz PCM, Base64).
- Floating capsule HUD with 5-bar waveform animation and live transcript display.
- Text injection via clipboard + simulated Cmd+V, with CJK input source switching.
- Two-step onboarding wizard (Accessibility permission + API key configuration).
- Persistent bilingual permission guide window with polling auto-close.
- Settings window: API key, model selection, connection test.
- Menu bar icon with language selector and quick access to settings.
- `make build / run / install / clean / qa / reset-permissions` build targets.
