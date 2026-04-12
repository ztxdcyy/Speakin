# Speakin

macOS 语音输入工具 —— 按住触发键说话，松开后文字自动输入到当前光标位置。

## 快速上手

1. 前往 [Releases](https://github.com/ztxdcyy/Speakin/releases) 下载最新的 `Speakin.dmg`
2. 打开 DMG，将 `Speakin.app` 拖入「应用程序」文件夹
3. 终端执行 `xattr -cr /Applications/Speakin.app`（解除 macOS 门禁限制）
4. 启动应用，按提示授予**辅助功能**和**麦克风**权限
5. 在菜单栏图标 → 设置中配置 [DashScope API Key](https://bailian.console.aliyun.com/)
6. 在任意输入框按住触发键说话，松开即输入（默认 Fn；可在设置中更改为 Right Option 等，兼容外接键盘）

## 特性

- **按住即说**：按住触发键开始录音，松开自动转写并输入（支持自定义热键，兼容外接键盘）
- **Paraformer-v2**：基于阿里云 DashScope Paraformer 实时语音识别，专为中文短语音优化
- **自动标点 & 语气词过滤**：输出自带标点，自动去除"嗯、啊"等口语
- **光标跟随**：胶囊 UI 自动定位到当前输入位置
- **多语言**：支持简体中文、English、日本語、한국어
- **CJK 智能切换**：自动处理中日韩输入法与粘贴的兼容问题
- **剪贴板无损**：注入文字后自动恢复原有剪贴板内容

## 系统要求

- macOS 13.0+
- 辅助功能权限（用于监听触发热键和模拟粘贴）
- 麦克风权限
- DashScope API Key（阿里云百炼平台）

## 配置

首次运行会弹出引导窗口：

1. 授予辅助功能权限
2. 配置 DashScope API Key（在菜单栏图标 → Settings 中设置）

## TODO

- [ ] **常用词录入** — 用户可在设置中添加自定义词汇表（如 "nixlbench" 等专业术语），注入 system prompt 提升识别准确率
- [ ] **本地推理** — 支持纯本地离线转写（基于 whisper.cpp 等），无需 API Key
- [ ] **润色文字** — 转写后可选对文字进行智能润色（修正语法、去口语化、调整格式等）
- [ ] **胶囊实时转写** — 在胶囊 HUD 中流式显示转写文字（当前仅在转写完成后直接注入光标）

## 更新记录

### v0.4.1 — 修复键盘劫持（macOS 26 beta）

macOS 26 beta 强化了 `NSEvent.mouseLocation` 的主线程要求，导致 CGEvent 回调阻塞、tap 反复被系统 disable，产生键盘劫持症状。已修复：所有 AppKit API 调用移出 CGEvent 回调。

### v0.4.0 — 自定义触发热键

**背景**：Speakin 最初绑定的触发键是苹果地球键（Fn），这个按键信号只存在于苹果原生键盘（MacBook 内置键盘、苹果薄膜键盘）。所有第三方外接键盘——无论机械键盘、罗技、雷蛇等——都不发送这个信号。这意味着笔记本合盖接外接键盘的场景下，Speakin 几乎无法使用。

**解决方案**：开放热键自定义。用户可以在设置中录制任意按键（Right Option、F13 等）作为触发键，不再依赖苹果专有按键。比指定某个固定替代键更自由，从根本上解决了外接键盘兼容问题。

### v0.3.0 — 矢量菜单栏图标

菜单栏图标改为 SVG 矢量格式，自动适配 macOS 深色/浅色模式。胶囊浮窗鸟图标升级为高分辨率透明背景版本。

### v0.2.0 — 切换至 Paraformer ASR

ASR 引擎从 Qwen-Omni-Realtime 换为 Paraformer-Realtime-v2，中文识别准确率大幅提升，胶囊 UI 重新设计为紧凑胶囊形态。

### v0.1.0 — 首次发布

Speakin 初始版本上线，支持 Fn 键按住录音、DashScope API 语音转写、文字注入光标。

---

## License

MIT
