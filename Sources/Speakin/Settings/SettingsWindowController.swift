import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var apiKeyField: NSTextField!
    private var statusLabel: NSTextField!
    private var apiKeyLabel: NSTextField!
    private var saveButton: NSButton!
    private var testButton: NSButton!
    private var brandIconView: NSImageView!

    // MARK: - Localized strings keyed by language code

    private static let strings: [String: [String: String]] = [
        "zh-CN": [
            "title": "Speakin 设置",
            "apiKeyLabel": "DashScope API Key",
            "save": "保存",
            "test": "测试",
            "saved": "设置已保存。",
            "enterKey": "请输入 API Key。",
            "connecting": "连接中...",
            "success": "连接成功！",
            "invalidKey": "API Key 无效或配额不足。",
            "unexpected": "意外的响应。",
            "timeout": "连接超时。",
        ],
        "en": [
            "title": "Speakin Settings",
            "apiKeyLabel": "DashScope API Key",
            "save": "Save",
            "test": "Test",
            "saved": "Settings saved.",
            "enterKey": "Please enter an API key.",
            "connecting": "Connecting...",
            "success": "Connection successful!",
            "invalidKey": "API key invalid or quota exceeded.",
            "unexpected": "Unexpected response.",
            "timeout": "Connection timed out.",
        ],
        "ja": [
            "title": "Speakin 設定",
            "apiKeyLabel": "DashScope API Key",
            "save": "保存",
            "test": "テスト",
            "saved": "設定を保存しました。",
            "enterKey": "API Key を入力してください。",
            "connecting": "接続中...",
            "success": "接続成功！",
            "invalidKey": "API Key が無効、またはクォータ超過です。",
            "unexpected": "予期しない応答です。",
            "timeout": "接続がタイムアウトしました。",
        ],
        "ko": [
            "title": "Speakin 설정",
            "apiKeyLabel": "DashScope API Key",
            "save": "저장",
            "test": "테스트",
            "saved": "설정이 저장되었습니다.",
            "enterKey": "API Key를 입력하세요.",
            "connecting": "연결 중...",
            "success": "연결 성공!",
            "invalidKey": "API Key가 유효하지 않거나 할당량을 초과했습니다.",
            "unexpected": "예상치 못한 응답입니다.",
            "timeout": "연결 시간이 초과되었습니다.",
        ],
    ]

    private func L(_ key: String) -> String {
        let lang = SettingsStore.shared.language
        return Self.strings[lang]?[key]
            ?? Self.strings["en"]![key]!
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshLocalization()
        super.showWindow(sender)
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let padding: CGFloat = 20
        let fieldHeight: CGFloat = 24
        let labelHeight: CGFloat = 17
        let fieldWidth: CGFloat = 380

        // Brand icon + name at top
        var y: CGFloat = 175

        brandIconView = NSImageView(frame: NSRect(x: padding, y: y - 4, width: 32, height: 32))
        brandIconView.imageScaling = .scaleProportionallyUpOrDown
        brandIconView.image = Bundle.main.image(forResource: "bird_icon_32")
        contentView.addSubview(brandIconView)

        let brandLabel = NSTextField(labelWithString: "Speakin")
        brandLabel.frame = NSRect(x: padding + 38, y: y, width: 200, height: 22)
        brandLabel.font = .systemFont(ofSize: 17, weight: .bold)
        brandLabel.textColor = .labelColor
        contentView.addSubview(brandLabel)

        y = 140

        // API Key label
        apiKeyLabel = makeLabel("", frame: NSRect(x: padding, y: y, width: fieldWidth, height: labelHeight))
        contentView.addSubview(apiKeyLabel)

        y -= fieldHeight + 4

        // API Key field
        apiKeyField = NSTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: fieldHeight))
        apiKeyField.placeholderString = "sk-xxxxxxxxxxxxxxxxxxxxxxxx"
        apiKeyField.font = .systemFont(ofSize: 13)
        contentView.addSubview(apiKeyField)

        y -= 40

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: padding, y: y, width: 200, height: labelHeight)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        // Buttons
        saveButton = NSButton(title: "", target: self, action: #selector(saveSettings))
        saveButton.frame = NSRect(x: 330, y: y - 4, width: 70, height: 28)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        testButton = NSButton(title: "", target: self, action: #selector(testConnection))
        testButton.frame = NSRect(x: 255, y: y - 4, width: 70, height: 28)
        testButton.bezelStyle = .rounded
        contentView.addSubview(testButton)

        refreshLocalization()
    }

    private func refreshLocalization() {
        window?.title = L("title")
        apiKeyLabel.stringValue = L("apiKeyLabel")
        saveButton.title = L("save")
        testButton.title = L("test")
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: 13, weight: .medium)
        return label
    }

    // MARK: - Load / Save

    private func loadSettings() {
        apiKeyField.stringValue = SettingsStore.shared.apiKey ?? ""
    }

    @objc private func saveSettings() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsStore.shared.apiKey = apiKey.isEmpty ? nil : apiKey

        statusLabel.stringValue = L("saved")
        statusLabel.textColor = .systemGreen
        NotificationCenter.default.post(name: .speakinSettingsSaved, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.window?.close()
        }
    }

    // MARK: - Test Connection

    @objc private func testConnection() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            statusLabel.stringValue = L("enterKey")
            statusLabel.textColor = .systemRed
            return
        }

        let connectingText = L("connecting")
        statusLabel.stringValue = connectingText
        statusLabel.textColor = .secondaryLabelColor

        let urlString = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"

        guard let url = URL(string: urlString) else {
            statusLabel.stringValue = "Invalid URL."
            statusLabel.textColor = .systemRed
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()

        // Send a minimal run-task to verify the API key is valid
        let taskID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let runTask: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": "paraformer-realtime-v2",
                "parameters": [
                    "sample_rate": 16000,
                    "format": "pcm"
                ] as [String: Any],
                "input": [String: Any]()
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: runTask),
           let jsonString = String(data: data, encoding: .utf8) {
            task.send(.string(jsonString)) { _ in }
        }

        // Listen for the first message (task-started or task-failed)
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message, text.contains("task-started") {
                        self.statusLabel.stringValue = self.L("success")
                        self.statusLabel.textColor = .systemGreen
                    } else if case .string(let text) = message, text.contains("task-failed") {
                        self.statusLabel.stringValue = self.L("invalidKey")
                        self.statusLabel.textColor = .systemRed
                    } else {
                        self.statusLabel.stringValue = self.L("unexpected")
                        self.statusLabel.textColor = .systemOrange
                    }
                case .failure(let error):
                    self.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    self.statusLabel.textColor = .systemRed
                }
                task.cancel(with: .goingAway, reason: nil)
            }
        }

        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            if self.statusLabel.stringValue == connectingText {
                self.statusLabel.stringValue = self.L("timeout")
                self.statusLabel.textColor = .systemRed
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}
