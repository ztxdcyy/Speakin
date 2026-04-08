import AppKit

enum CapsuleState {
    case hidden
    case recording
    case waitingForResult
    case error(String)
}

class CapsulePanel: NSPanel {
    private let effectView: NSVisualEffectView
    private let waveformView: WaveformView
    private let errorLabel: TranscriptLabel
    private let spinner: NSProgressIndicator

    /// Floating bird icon shown outside the capsule (to its left) during recording.
    private var birdWindow: NSPanel?

    // Capsule shape: horizontal pill / rounded rectangle
    private let capsuleWidth: CGFloat = 72
    private let capsuleHeight: CGFloat = 32
    private var capsuleCornerRadius: CGFloat { capsuleHeight / 2 }
    private let waveformSize = NSSize(width: 36, height: 20)
    private let spinnerSize: CGFloat = 16

    /// Size of the floating bird icon outside the capsule
    private let birdSize: CGFloat = 60
    /// Gap between bird and capsule
    private let birdGap: CGFloat = 6

    /// Wider size used when showing error text
    private let errorPadding: CGFloat = 10
    private let errorTextWidth: CGFloat = 160

    private(set) var state: CapsuleState = .hidden

    /// Cached caret position — captured early (before panel steals focus)
    private var cachedCaretRect: NSRect?

    // MARK: - Init

    init() {
        // Setup visual effect view
        effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16  // capsuleHeight / 2
        effectView.layer?.masksToBounds = true

        // Waveform — centered in the capsule
        waveformView = WaveformView(frame: NSRect(
            x: (72 - waveformSize.width) / 2,
            y: (32 - waveformSize.height) / 2,
            width: waveformSize.width,
            height: waveformSize.height
        ))

        // Error label (only used for error state, hidden normally)
        let labelX: CGFloat = 72 + errorPadding
        errorLabel = TranscriptLabel(frame: NSRect(
            x: labelX,
            y: 0,
            width: errorTextWidth,
            height: 32
        ))
        errorLabel.isHidden = true

        // Spinner — centered in the capsule
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.frame = NSRect(
            x: (72 - spinnerSize) / 2,
            y: (32 - spinnerSize) / 2,
            width: spinnerSize,
            height: spinnerSize
        )
        spinner.isHidden = true

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 32),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        setupSubviews()
    }

    private func configurePanel() {
        appearance = NSAppearance(named: .darkAqua)
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func setupSubviews() {
        guard let contentView = self.contentView else { return }

        effectView.frame = contentView.bounds
        effectView.autoresizingMask = [.width, .height]
        contentView.addSubview(effectView)

        effectView.addSubview(waveformView)
        effectView.addSubview(spinner)
        effectView.addSubview(errorLabel)
    }

    // MARK: - State Management

    func setState(_ newState: CapsuleState) {
        AppLogger.shared.log("[Capsule] setState: \(newState), panelW=\(frame.width)")
        state = newState

        switch newState {
        case .hidden:
            hideAnimated()

        case .recording:
            errorLabel.reset()
            errorLabel.isHidden = true
            waveformView.reset()
            waveformView.isHidden = false
            waveformView.startAnimating()
            spinner.isHidden = true
            spinner.stopAnimation(nil)
            resizeToCompact()
            ensureVisible()
            showBirdWindow()

        case .waitingForResult:
            waveformView.stopAnimating()
            waveformView.isHidden = true
            errorLabel.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
            hideBirdWindow()
            resizeToCompact()
            ensureVisible()

        case .error(let message):
            waveformView.stopAnimating()
            waveformView.isHidden = true
            spinner.isHidden = true
            spinner.stopAnimation(nil)
            hideBirdWindow()
            errorLabel.text = message
            errorLabel.isHidden = false
            resizeForError()
            ensureVisible()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if case .error = self?.state {
                    self?.setState(.hidden)
                }
            }
        }
    }

    /// Ensure the panel is on screen and visible
    private func ensureVisible() {
        if !isVisible {
            positionNearCursor()
            alphaValue = 0
            contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.8, y: 0.8))
            orderFrontRegardless()

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                self.animator().alphaValue = 1
                self.contentView?.layer?.setAffineTransform(.identity)
            })
        }
    }

    // MARK: - Content Updates

    func updateWaveformLevel(_ level: Float) {
        waveformView.updateLevel(level)
    }

    func updateTranscript(_ text: String) {
        // In compact mode, transcript is not displayed in the capsule.
        // Kept as no-op for protocol compatibility.
    }

    /// Cache a pre-captured caret position for use when the capsule becomes visible.
    /// The rect should be captured early (e.g. in CGEvent callback) while the frontmost app has focus.
    func cacheCaretPosition(_ rect: NSRect?) {
        cachedCaretRect = rect
        if let r = rect {
            AppLogger.shared.log("[Capsule] cached caret: \(r)")
        } else {
            AppLogger.shared.log("[Capsule] cached caret: nil (will use fallback)")
        }
    }

    // MARK: - Panel Sizing

    /// Compact mode: pill-shaped capsule with just the icon
    private func resizeToCompact() {
        var newFrame = frame
        newFrame.size.width = capsuleWidth
        newFrame.size.height = capsuleHeight
        setFrame(newFrame, display: true)
        effectView.layer?.cornerRadius = capsuleCornerRadius
    }

    /// Error mode: expand to show error text
    private func resizeForError() {
        let totalWidth = capsuleWidth + errorTextWidth + errorPadding
        var newFrame = frame
        newFrame.size.width = totalWidth
        newFrame.size.height = capsuleHeight
        setFrame(newFrame, display: true)
        effectView.layer?.cornerRadius = capsuleCornerRadius
    }

    // MARK: - Position

    private func positionNearCursor() {
        // Use cached caret (captured early), fall back to live query, then screen center
        let caretRect = cachedCaretRect ?? Self.getCaretRect()
        cachedCaretRect = nil  // consume cache

        if let caretRect = caretRect {
            guard let screen = NSScreen.main else {
                positionAtScreenBottom()
                return
            }
            let screenFrame = screen.frame
            AppLogger.shared.log("[Capsule] caretRect=\(caretRect), screenFrame=\(screenFrame)")

            let gap: CGFloat = 6  // spacing between caret and capsule

            // Default: place capsule to the upper-right of the caret
            var x = caretRect.maxX + gap
            var y = caretRect.maxY + gap

            // If capsule overflows right edge, flip to upper-left
            if x + frame.width > screenFrame.maxX - 10 {
                x = caretRect.origin.x - frame.width - gap
            }
            // If still overflows left, clamp to left edge
            if x < screenFrame.origin.x + 10 {
                x = screenFrame.origin.x + 10
            }
            // If capsule overflows top edge, place below caret instead
            if y + frame.height > screenFrame.maxY - 10 {
                y = caretRect.origin.y - frame.height - gap
            }
            // If overflows bottom, clamp
            if y < screenFrame.origin.y + 10 {
                y = screenFrame.origin.y + 10
            }

            setFrameOrigin(NSPoint(x: x, y: y))
            return
        }

        AppLogger.shared.log("[Capsule] caret not found, falling back to screen bottom center")
        positionAtScreenBottom()
    }

    private func positionAtScreenBottom() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth = max(frame.width, capsuleWidth)
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screenFrame.origin.y + 80
        AppLogger.shared.log("[Capsule] fallback position: x=\(x), y=\(y), panelW=\(panelWidth)")
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Use Accessibility API (system-wide) to get the caret position.
    /// Uses AXUIElementCreateSystemWide to avoid frontmostApplication issues.
    /// Short messaging timeout (150ms) prevents blocking if target app is unresponsive.
    private static func getCaretRect() -> NSRect? {
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, 0.15)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            AppLogger.shared.log("[Capsule] AX: cannot get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            AppLogger.shared.log("[Capsule] AX: cannot get selected text range")
            return nil
        }

        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &boundsValue
        ) == .success else {
            AppLogger.shared.log("[Capsule] AX: cannot get bounds for range")
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else {
            AppLogger.shared.log("[Capsule] AX: cannot extract CGRect")
            return nil
        }

        // AX coordinates: origin at top-left of main screen. Convert to AppKit (bottom-left).
        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - rect.origin.y - rect.size.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }

    // MARK: - Animations

    private func hideAnimated() {
        guard let layer = contentView?.layer else {
            orderOut(nil)
            resetPanelSize()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
            layer.setAffineTransform(CGAffineTransform(scaleX: 0.85, y: 0.85))
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            layer.setAffineTransform(.identity)
            self?.alphaValue = 1
            self?.waveformView.stopAnimating()
            self?.waveformView.reset()
            self?.resetPanelSize()
        })
    }

    /// Reset panel to compact capsule size
    private func resetPanelSize() {
        errorLabel.reset()
        errorLabel.isHidden = true
        var newFrame = frame
        newFrame.size.width = capsuleWidth
        newFrame.size.height = capsuleHeight
        setFrame(newFrame, display: false)
    }

    // MARK: - Floating Bird Window

    /// Show a colorful bird icon floating to the left of the capsule.
    private func showBirdWindow() {
        if birdWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: birdSize, height: birdSize),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.level = .statusBar
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: birdSize, height: birdSize))
            imageView.image = Bundle.main.image(forResource: "bird_capsule")
            imageView.imageScaling = .scaleProportionallyUpOrDown
            panel.contentView = imageView

            birdWindow = panel
        }

        positionBirdWindow()
        birdWindow?.alphaValue = 0
        birdWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.birdWindow?.animator().alphaValue = 1
        }
    }

    /// Position the bird window to the left of the capsule.
    private func positionBirdWindow() {
        let capsuleFrame = self.frame
        let x = capsuleFrame.origin.x - birdSize - birdGap
        let y = capsuleFrame.origin.y + (capsuleFrame.height - birdSize) / 2
        birdWindow?.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Hide the floating bird window.
    private func hideBirdWindow() {
        guard let bird = birdWindow, bird.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            bird.animator().alphaValue = 0
        }, completionHandler: {
            bird.orderOut(nil)
            bird.alphaValue = 1
        })
    }
}
