# Changelog

All notable changes to Speakin will be documented in this file.

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
