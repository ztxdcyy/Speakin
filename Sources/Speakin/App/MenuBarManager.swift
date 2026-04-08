import AppKit
import ServiceManagement

class MenuBarManager {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    static let shared = MenuBarManager()

    // MARK: - Localized menu strings keyed by language code

    private static let menuStrings: [String: [String: String]] = [
        "zh-CN": [
            "language": "语言",
            "languageHint": "同时切换界面和语音识别语言",
            "settings": "设置...",
            "launchAtLogin": "开机自启",
            "quit": "退出 Speakin",
        ],
        "en": [
            "language": "Language",
            "languageHint": "Switches both UI and speech recognition",
            "settings": "Settings...",
            "launchAtLogin": "Launch at Login",
            "quit": "Quit Speakin",
        ],
        "ja": [
            "language": "言語",
            "languageHint": "UIと音声認識の両方を切り替えます",
            "settings": "設定...",
            "launchAtLogin": "ログイン時に起動",
            "quit": "Speakin を終了",
        ],
        "ko": [
            "language": "언어",
            "languageHint": "UI 및 음성 인식 언어를 모두 전환합니다",
            "settings": "설정...",
            "launchAtLogin": "로그인 시 실행",
            "quit": "Speakin 종료",
        ],
    ]

    /// Get a localized menu string for the current language, falling back to English.
    private func localizedString(_ key: String) -> String {
        let lang = SettingsStore.shared.language
        return Self.menuStrings[lang]?[key]
            ?? Self.menuStrings["en"]![key]!
    }

    init() {
        setupStatusItem()
        buildMenu()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.loadMenuBarImage()
        }
    }

    func setRecording(_ recording: Bool) {
        // Currently a no-op; the menu bar icon stays the same during recording.
        // The capsule floating bird provides the recording visual indicator.
    }

    /// Load the bird SVG template image from bundle resources for the menu bar.
    /// The SVG is a potrace-vectorized version of the logo, pure black paths on transparent
    /// background, suitable for use as a template image (auto-adapts to light/dark mode).
    private static func loadMenuBarImage() -> NSImage? {
        guard let svgURL = Bundle.main.url(forResource: "bird_menubar", withExtension: "svg"),
              let image = NSImage(contentsOf: svgURL) else {
            AppLogger.shared.log("WARNING: Failed to load bird_menubar.svg from bundle")
            return nil
        }
        image.size = NSSize(width: 30, height: 30)
        image.isTemplate = true
        return image
    }

    // MARK: - Menu

    private func buildMenu() {
        menu = NSMenu()

        // Language submenu
        let languageItem = NSMenuItem(title: localizedString("language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()

        // Hint label explaining this setting controls both UI and ASR
        let hintItem = NSMenuItem(title: localizedString("languageHint"), action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        languageMenu.addItem(hintItem)
        languageMenu.addItem(NSMenuItem.separator())

        let languages: [(String, String)] = [
            ("简体中文", "zh-CN"),
            ("English", "en"),
            ("日本語", "ja"),
            ("한국어", "ko"),
        ]

        for (name, code) in languages {
            let item = NSMenuItem(title: name, action: #selector(languageSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            if SettingsStore.shared.language == code {
                item.state = .on
            }
            languageMenu.addItem(item)
        }

        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: localizedString("settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Launch at Login
        let launchItem = NSMenuItem(title: localizedString("launchAtLogin"), action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = SettingsStore.shared.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: localizedString("quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func languageSelected(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        SettingsStore.shared.language = code

        // Rebuild entire menu so all labels update to the new language
        buildMenu()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = !SettingsStore.shared.launchAtLogin
        SettingsStore.shared.launchAtLogin = newValue
        sender.state = newValue ? .on : .off

        if #available(macOS 13.0, *) {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[Speakin] Failed to update login item: \(error)")
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
