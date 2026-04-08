# CODEBUDDY.md This file provides guidance to CodeBuddy when working with code in this repository.

## Build & Run Commands

| Command | Description |
|---------|-------------|
| `make build` | Release build via `swift build -c release`, creates signed `.app` bundle at `.build/release/Speakin.app`. Requires `Speakin Dev` code signing certificate (run `make setup-cert` first if missing). |
| `make run` | Build then launch the app (kills any running instance first). |
| `make clean` | Remove all build artifacts (`swift package clean && rm -rf .build`). |
| `make qa` | Build then verify app bundle integrity (binary + Info.plist existence). |
| `make release` | Unsigned release build + zip package for distribution. |
| `make reset-permissions` | Reset TCC Accessibility permission for the bundle ID (useful when debugging permission issues). |
| `make setup-cert` | Create self-signed `Speakin Dev` code signing certificate if not present. |
| `swift build` | Debug build only (no `.app` bundle packaging). |

There are no automated tests. Validation is manual via `QA_CHECKLIST.md`.

## Development Workflow (from RULE.md)

Follow the cycle: **提问 → Plan → Action → Check**. After completing a task, run `make run` to compile and wait for manual testing.

- **Progress persistence**: Update `progress.txt` (free-form log), `features.json` (only update `status` field), and git commits to maintain continuity across sessions.
- **Plan before execute**: Multi-file or architectural changes require a written plan before coding. Small changes can go straight to implementation.
- Debug flags and log statements are welcome during development. Logs go to `~/Library/Logs/Speakin/`.

## Architecture Overview

Speakin is a macOS menu bar app (LSUIElement) for voice-to-text input. The user holds the Fn key to record speech, which is streamed to Alibaba DashScope's Paraformer ASR API via WebSocket, and the transcribed text is injected into the currently focused input field. Built with pure AppKit (no SwiftUI), Swift 5.9, SPM, and zero third-party dependencies.

### Entry Point & Initialization

`main.swift` creates `NSApplication` and sets `AppDelegate` as delegate. The startup sequence in `AppDelegate.applicationDidFinishLaunching`:

1. Creates a hidden Edit menu (LSUIElement apps need this for Cmd+C/V/X/A in text fields)
2. Loads `SettingsStore.shared`
3. Creates `MenuBarManager.shared` (status bar icon + dropdown menu)
4. Creates `SessionCoordinator` and wires it as `FnKeyMonitor.shared.delegate`
5. Runs `PermissionManager.shared.checkAndRequestPermissions()`
6. Starts `FnKeyMonitor.shared.start()`
7. Listens for `.accessibilityPermissionGranted` notification to restart FnKeyMonitor

### SessionCoordinator — The Central Orchestrator

`SessionCoordinator` is the **single hub** that ties all modules together. It implements three delegate protocols: `FnKeyMonitorDelegate`, `AudioEngineDelegate`, `SpeechClientDelegate`. It directly owns (non-singleton) instances of `AudioEngine`, `SpeechClient`, and `CapsulePanel`.

**State machine** (`SessionState`):
```
idle ──[Fn press]──▶ connecting ──[task-started]──▶ recording ──[Fn release]──▶ waitingForResult ──[task-finished]──▶ injecting ──▶ idle
                          │                              │                            │
                    [Fn release/error]               [error]                    [timeout 15s/error]
                          └──────────────────────────────┘────────────────────────────┘──▶ idle
```

**Full session flow**:
1. Fn pressed → check API key → cache caret position → connect WebSocket → show capsule spinner
2. WebSocket `task-started` → start `AudioEngine` recording → capsule shows waveform
3. Audio tap callback: compute RMS (→ waveform animation) + manual downsample 48kHz→16kHz + Base64 encode → send binary frames to ASR
4. Fn released → if held < 300ms, cancel (anti-bounce); otherwise stop recording → send `finish-task` → start 15s timeout
5. Receive `task-finished` → get `fullTranscript` → `TextInjector.inject()` → hide capsule → idle

### Module Communication Patterns

| From → To | Mechanism |
|-----------|-----------|
| FnKeyMonitor → SessionCoordinator | `FnKeyMonitorDelegate` (delegate) |
| AudioEngine → SessionCoordinator | `AudioEngineDelegate` (delegate) |
| SpeechClient → SessionCoordinator | `SpeechClientDelegate` (delegate) |
| SessionCoordinator → CapsulePanel | Direct method calls |
| SessionCoordinator → MenuBarManager | `MenuBarManager.shared` singleton |
| SessionCoordinator → TextInjector | `TextInjector.inject()` static method |
| PermissionManager → AppDelegate | NotificationCenter (`.accessibilityPermissionGranted`) |
| SettingsWindowController → PermissionManager | NotificationCenter (`.speakinSettingsSaved`) |
| PermissionManager → PermissionGuideWindowController | Closure callbacks (`onOpenSettings`, `onRecheck`, etc.) |

### Singletons vs Owned Instances

**Singletons** (`.shared`): `AppLogger`, `PermissionDebugLogger`, `MenuBarManager`, `PermissionManager`, `SettingsStore`, `SettingsWindowController`, `FnKeyMonitor`.

**Owned by SessionCoordinator** (not singletons): `AudioEngine`, `SpeechClient`, `CapsulePanel`.

### Key Module Details

**Audio (`Audio/`)**: `AudioEngine` uses `AVAudioEngine` with `installTap` on hardware format. Downsampling from hardware rate (typically 48kHz) to 16kHz is done **manually with linear interpolation** — not via `AVAudioConverter` (which caused audio duplication artifacts). RMS callbacks go to main thread; PCM processing runs on a `.userInteractive` dispatch queue.

**HotKey (`HotKey/FnKeyMonitor.swift`)**: Uses `CGEvent.tapCreate(.cgSessionEventTap, .defaultTap)` to intercept `flagsChanged` events. Detects `.maskSecondaryFn` flag. Returns `nil` to swallow Fn events and prevent the system Emoji Picker. Captures caret position **synchronously in the C callback** (before event is swallowed) via Accessibility API, with mouse position as fallback for Electron apps. Has `reEnableIfNeeded()` to handle tap being disabled after system sleep, with hardware state sync to prevent stuck `fnPressed`.

**WebSocket (`WebSocket/`)**: The app has **two** WebSocket clients:
- `SpeechClient` — **currently active**. Model-agnostic DashScope streaming ASR client using `/api-ws/v1/inference`. Currently configured with `paraformer-realtime-v2` model and semantic punctuation enabled (`semantic_punctuation_enabled: true`) for smarter sentence boundary detection during pauses. Protocol: `run-task` → `task-started` → binary audio frames → `finish-task` → `task-finished`. Accumulates final sentences in `finalSentences` array.
- `RealtimeAPIClient` — **legacy, not used by SessionCoordinator**. Was the original Qwen-Omni Realtime API client at `/api-ws/v1/realtime`. Retained in codebase but not wired up.

Both clients use `connectionID` to guard against stale callbacks from old connections.

**TextInjection (`TextInjection/`)**: `TextInjector.inject()` follows a precise sequence: backup clipboard → write text → detect CJK input method → temporarily switch to ASCII (50ms delay) → simulate Cmd+V via `CGEvent` → restore input method (150ms) → restore clipboard (200ms). `InputSourceManager` uses Carbon `TISInputSource` APIs.

**UI (`UI/`)**: `CapsulePanel` is a 72×32px `NSPanel` (.nonactivatingPanel, won't steal focus) with dark HUD material. Positions near the text caret using cached AX position, with smart overflow handling. States: hidden, recording (waveform), waitingForResult (spinner), error (auto-dismiss after 2s). `WaveformView` draws 5 bars with CoreGraphics at 60fps, driven by RMS with attack/release envelope smoothing.

**Permission System (`App/PermissionManager.swift`)**: Tests Accessibility by actually creating a `CGEvent.tapCreate(.defaultTap)` (more reliable than `AXIsProcessTrusted`). Shows a two-step guide window: Step 1 = Accessibility permission with 1.5s polling auto-detect; Step 2 = API Key configuration. Listens for `.speakinSettingsSaved` to refresh API status in the guide.

**Settings (`Settings/`)**: `SettingsStore` uses custom `@UserDefault` / `@OptionalUserDefault` property wrappers over `UserDefaults`. Keys: `speakin_apiKey`, `speakin_model` (default: `qwen-omni-turbo-realtime-latest`), `speakin_language` (default: `zh-CN`), `speakin_launchAtLogin`. `SettingsWindowController` includes a Test button that attempts a WebSocket connection with 5s timeout.

### Custom Notification Names

Defined in `PermissionManager.swift`:
- `.accessibilityPermissionGranted` — triggers FnKeyMonitor restart
- `.microphonePermissionGranted`
- `.speakinSettingsSaved` — triggers guide window API status refresh
