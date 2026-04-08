import AppKit
import CoreGraphics
import Foundation

protocol FnKeyMonitorDelegate: AnyObject {
    func fnKeyDidPress()
    func fnKeyDidRelease()
}

class FnKeyMonitor {
    static let shared = FnKeyMonitor()

    weak var delegate: FnKeyMonitorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnPressed = false

    /// Caret rect captured synchronously in the CGEvent callback (before event is swallowed).
    /// Accessed from CGEvent callback thread + main thread, protected by the fact that
    /// main.async reads happen after the write.
    private(set) var lastCaretRect: NSRect?

    private init() {}

    // MARK: - Start / Stop

    func start() {
        guard eventTap == nil else {
            AppLogger.shared.log("[FnKey] start() skipped — tap already exists")
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: fnEventCallback,
            userInfo: userInfo
        ) else {
            AppLogger.shared.log("[FnKey] FAILED to create CGEvent tap — no accessibility permission?")
            return
        }

        eventTap = tap

        // Sync state with hardware before enabling, in case app started while Fn held
        fnPressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        AppLogger.shared.log("[FnKey] Monitor started successfully. delegate=\(delegate != nil ? "set" : "nil")")
    }

    func stop() {
        if let tap = eventTap {
            // Disable first so no more events are intercepted
            CGEvent.tapEnable(tap: tap, enable: false)
            // Invalidate the MachPort so the tap is fully removed from the system
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        fnPressed = false
        AppLogger.shared.log("[FnKey] monitor stopped, tap destroyed")
    }

    // MARK: - Event Handling

    /// Modifier flags that are NOT the Fn key — used to decide whether to swallow the event.
    private static let nonFnModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskAlphaShift
    ]

    /// Returns whether the event should be suppressed (true = swallow pure-Fn events only).
    fileprivate func handleFlagsChanged(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let isFn = flags.contains(.maskSecondaryFn)

        if isFn && !fnPressed {
            fnPressed = true
            AppLogger.shared.log("[FnKey] Fn DOWN detected")

            // Capture mouse position immediately (safe, non-blocking).
            // AX caret query is deferred to main.async to avoid blocking the event pipeline.
            let mouseRect = Self.mousePositionRect()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Try AX caret query with short timeout; fall back to mouse position.
                self.lastCaretRect = Self.captureCaretRect() ?? mouseRect
                self.delegate?.fnKeyDidPress()
            }

            // Only swallow if this is a PURE Fn press (no other modifiers).
            // If Cmd/Shift/Option/Control are also held, let the event through
            // so the system sees those modifier state changes.
            let hasOtherModifiers = !flags.intersection(Self.nonFnModifiers).isEmpty
            return !hasOtherModifiers

        } else if !isFn && fnPressed {
            fnPressed = false
            AppLogger.shared.log("[FnKey] Fn UP detected")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.fnKeyDidRelease()
            }

            let hasOtherModifiers = !flags.intersection(Self.nonFnModifiers).isEmpty
            return !hasOtherModifiers
        }

        return false
    }

    /// Capture the caret rect using Accessibility API.
    /// Uses a short messaging timeout (150ms) to avoid blocking if the target app is unresponsive.
    /// Should be called from main thread (moved out of CGEvent callback for safety).
    private static func captureCaretRect() -> NSRect? {
        let systemElement = AXUIElementCreateSystemWide()
        // Set a short timeout so we never block for the default ~5 seconds
        AXUIElementSetMessagingTimeout(systemElement, 0.15)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            AppLogger.shared.log("[FnKey] AX: cannot get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            AppLogger.shared.log("[FnKey] AX: cannot get selected text range")
            return nil
        }

        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &boundsValue
        ) == .success else {
            AppLogger.shared.log("[FnKey] AX: cannot get bounds for range")
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // AX coordinates: origin at top-left of main screen. Convert to AppKit (bottom-left).
        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - rect.origin.y - rect.size.height
        let result = NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
        AppLogger.shared.log("[FnKey] captured caret: \(result)")
        return result
    }

    /// Fallback: use the current mouse position as an approximate caret location.
    /// Works for apps like VS Code (Electron) where AX text caret is unavailable.
    private static func mousePositionRect() -> NSRect? {
        let mouseLocation = NSEvent.mouseLocation  // AppKit coordinates (bottom-left origin)
        AppLogger.shared.log("[FnKey] fallback to mouse position: \(mouseLocation)")
        return NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 0, height: 18)
    }

    /// Re-enable the tap if macOS disables it (e.g. after sleep).
    /// MUST sync fnPressed with actual hardware state first — if the tap was
    /// disabled while Fn was held and missed the Fn-UP event, fnPressed would
    /// be stuck true, causing all subsequent modifier-key events to be
    /// suppressed (keyboard hijack).
    func reEnableIfNeeded() {
        if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            fnPressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
            CGEvent.tapEnable(tap: tap, enable: true)
            AppLogger.shared.log("[FnKey] tap re-enabled, synced fnPressed=\(fnPressed)")
        }
    }
}

// MARK: - C Callback

private func fnEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Handle tap disabled by system
    if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        if let userInfo = userInfo {
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.reEnableIfNeeded()
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .flagsChanged, let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let shouldSuppress = monitor.handleFlagsChanged(event)

    if shouldSuppress {
        return nil // swallow event to prevent emoji picker
    }

    return Unmanaged.passRetained(event)
}
