import Cocoa
import Carbon
import ApplicationServices
import Combine
import os

enum PopupHotkeyPressMode: String, CaseIterable, Identifiable {
    case singlePress
    case doublePress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singlePress:
            return "Single press"
        case .doublePress:
            return "Double press"
        }
    }
}

struct ShortcutModifiers: OptionSet, Equatable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let shift = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let control = ShortcutModifiers(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(eventFlags: CGEventFlags) {
        var result: ShortcutModifiers = []
        if eventFlags.contains(.maskCommand) { result.insert(.command) }
        if eventFlags.contains(.maskShift) { result.insert(.shift) }
        if eventFlags.contains(.maskAlternate) { result.insert(.option) }
        if eventFlags.contains(.maskControl) { result.insert(.control) }
        self = result
    }

    init(modifierFlags: NSEvent.ModifierFlags) {
        var result: ShortcutModifiers = []
        if modifierFlags.contains(.command) { result.insert(.command) }
        if modifierFlags.contains(.shift) { result.insert(.shift) }
        if modifierFlags.contains(.option) { result.insert(.option) }
        if modifierFlags.contains(.control) { result.insert(.control) }
        self = result
    }

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        return flags
    }

    var displaySymbols: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

struct KeyboardShortcut: Equatable {
    var keyCode: Int64
    var modifiers: ShortcutModifiers

    var displayString: String {
        "\(modifiers.displaySymbols)\(KeyboardShortcut.displayKey(for: keyCode))"
    }

    private static func displayKey(for keyCode: Int64) -> String {
        switch keyCode {
        case 36: return "↩︎"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            break
        }

        let table: [Int64: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            50: "`"
        ]

        return table[keyCode] ?? "Key \(keyCode)"
    }
}

class KeyboardMonitor: ObservableObject {
    var onPopupHotkey: ((RichTextPayload) -> Void)?
    @Published var isCustomActionHotkeysEnabled: Bool = false
    @Published var customActionHotkey: Int?
    @Published var popupHotkey: KeyboardShortcut
    @Published var popupHotkeyPressMode: PopupHotkeyPressMode
    
    private var lastPopupHotkeyPressTime: Date?
    private let doublePressInterval: TimeInterval = 0.5
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isProcessing: Bool = false // Protection against multiple triggers
    private var isProcessingCustomAction: Bool = false
    private var isSimulatingCopy: Bool = false
    private var setupRetryCount: Int = 0
    private let setupRetryLimit: Int = 10
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TinyAI", category: "KeyboardMonitor")

    private let popupHotkeyKeyCodeDefaultsKey = "PopupHotkeyKeyCodeV1"
    private let popupHotkeyModifiersDefaultsKey = "PopupHotkeyModifiersV1"
    private let popupHotkeyPressModeDefaultsKey = "PopupHotkeyPressModeV1"

    private static let customActionKeyCodeToIndex: [Int64: Int] = [
        18: 1, // 1
        19: 2, // 2
        20: 3, // 3
        21: 4, // 4
        23: 5  // 5
    ]
    
    init() {
        let defaults = UserDefaults.standard
        let savedKeyCode = defaults.object(forKey: popupHotkeyKeyCodeDefaultsKey) as? Int64
        let savedModifiers = defaults.object(forKey: popupHotkeyModifiersDefaultsKey) as? Int
        let savedPressModeRaw = defaults.string(forKey: popupHotkeyPressModeDefaultsKey)

        let defaultHotkey = KeyboardShortcut(keyCode: 8, modifiers: [.command]) // ⌘C
        popupHotkey = KeyboardShortcut(
            keyCode: savedKeyCode ?? defaultHotkey.keyCode,
            modifiers: ShortcutModifiers(rawValue: savedModifiers ?? defaultHotkey.modifiers.rawValue)
        )
        popupHotkeyPressMode = PopupHotkeyPressMode(rawValue: savedPressModeRaw ?? "") ?? .doublePress

        if savedKeyCode == nil || savedModifiers == nil {
            defaults.set(popupHotkey.keyCode, forKey: popupHotkeyKeyCodeDefaultsKey)
            defaults.set(popupHotkey.modifiers.rawValue, forKey: popupHotkeyModifiersDefaultsKey)
        }
        if savedPressModeRaw == nil {
            defaults.set(popupHotkeyPressMode.rawValue, forKey: popupHotkeyPressModeDefaultsKey)
        }

        setupGlobalHotkey()
    }
    
    deinit {
        stopMonitoring()
    }

    func validatePopupHotkey(_ shortcut: KeyboardShortcut, pressMode: PopupHotkeyPressMode) -> String? {
        guard shortcut.modifiers.contains(.command) else {
            return "Shortcut must include ⌘ (Command)."
        }

        let reservedDigitKeyCodes: Set<Int64> = [18, 19, 20, 21, 22, 23, 25, 26, 28, 29]
        if reservedDigitKeyCodes.contains(shortcut.keyCode) && shortcut.modifiers == [.command] {
            return "⌘1, ⌘2, ⌘3, … are static shortcuts and can’t be reassigned."
        }

        // Always-reserved system-level shortcuts.
        if shortcut.modifiers == [.command] && shortcut.keyCode == 49 { // ⌘Space
            return "⌘Space is reserved by the system."
        }
        if shortcut.modifiers == [.command] && shortcut.keyCode == 48 { // ⌘Tab
            return "⌘Tab is reserved by the system."
        }
        let screenshotKeyCodes: Set<Int64> = [20, 21, 23] // 3/4/5
        if shortcut.modifiers == [.command, .shift] && screenshotKeyCodes.contains(shortcut.keyCode) { // ⌘⇧3/4/5
            return "⌘⇧3/4/5 are reserved by the system for screenshots."
        }

        // Common system/app editing shortcuts: disallow for single-press so we don’t override them.
        if pressMode == .singlePress && shortcut.modifiers == [.command] {
            let reservedSinglePress: Set<Int64> = [
                0,  // A
                6,  // Z
                7,  // X
                8,  // C
                9,  // V
                1,  // S
                12, // Q
                13, // W
                50  // `
            ]
            if reservedSinglePress.contains(shortcut.keyCode) {
                return "This shortcut already has a system-defined action (Copy/Paste/Undo/etc)."
            }
        }

        return nil
    }

    func applyPopupHotkeySettings(shortcut: KeyboardShortcut, pressMode: PopupHotkeyPressMode) -> String? {
        if let error = validatePopupHotkey(shortcut, pressMode: pressMode) {
            return error
        }

        popupHotkey = shortcut
        popupHotkeyPressMode = pressMode

        let defaults = UserDefaults.standard
        defaults.set(shortcut.keyCode, forKey: popupHotkeyKeyCodeDefaultsKey)
        defaults.set(shortcut.modifiers.rawValue, forKey: popupHotkeyModifiersDefaultsKey)
        defaults.set(pressMode.rawValue, forKey: popupHotkeyPressModeDefaultsKey)
        return nil
    }

    private func setupGlobalHotkey() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            logger.error("Failed to create event tap")
            scheduleSetupRetryIfNeeded()
            return
        }

        setupRetryCount = 0
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func scheduleSetupRetryIfNeeded() {
        guard setupRetryCount < setupRetryLimit else {
            return
        }

        setupRetryCount += 1
        let delay = min(5.0, 0.5 + (Double(setupRetryCount) * 0.5))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.eventTap == nil {
                self.setupGlobalHotkey()
            }
        }
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            if isSimulatingCopy {
                return Unmanaged.passUnretained(event)
            }

            let observedModifiers = ShortcutModifiers(eventFlags: flags)

            if isCustomActionHotkeysEnabled && NSApp.isActive && observedModifiers == [.command] {
                if let index = Self.customActionKeyCodeToIndex[keyCode], !isProcessingCustomAction {
                    isProcessingCustomAction = true
                    DispatchQueue.main.async { [weak self] in
                        self?.customActionHotkey = index
                        DispatchQueue.main.async { [weak self] in
                            self?.customActionHotkey = nil
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.isProcessingCustomAction = false
                    }
                    return nil
                }
            }
            
            if keyCode == popupHotkey.keyCode && observedModifiers == popupHotkey.modifiers {
                let now = Date()
                switch popupHotkeyPressMode {
                case .singlePress:
                    if !isProcessing {
                        isProcessing = true
                        DispatchQueue.main.async { [weak self] in
                            self?.handlePopupHotkeyTriggered()
                        }
                    }
                    return nil
                case .doublePress:
                    if let lastPress = lastPopupHotkeyPressTime,
                       now.timeIntervalSince(lastPress) < doublePressInterval {
                        if !isProcessing {
                            isProcessing = true
                            DispatchQueue.main.async { [weak self] in
                                self?.handlePopupHotkeyTriggered()
                            }
                        }
                        return nil
                    }

                    lastPopupHotkeyPressTime = now
                    return Unmanaged.passUnretained(event)
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handlePopupHotkeyTriggered() {
        // Ensure we are on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handlePopupHotkeyTriggered()
            }
            return
        }
        
        if let payload = getSelectedRichText(), !payload.plain.isEmpty {
            onPopupHotkey?(payload)
            // Reset the flag after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.isProcessing = false
            }
        } else {
            // Fallback: use the pasteboard
            let pasteboard = NSPasteboard.general
            let snapshot = snapshotPasteboard(pasteboard)

            // Copy selected text
            isSimulatingCopy = true
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C key
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            // Small delay to allow the copy to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                let payload = RichTextPasteboard.read(from: pasteboard)
                if let payload, !payload.plain.isEmpty {
                    DispatchQueue.main.async {
                        self.onPopupHotkey?(payload)
                    }
                }
                // Restore previous pasteboard contents
                restorePasteboard(pasteboard, snapshot: snapshot)
                self.isSimulatingCopy = false
                // Reset the flag after processing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    self.isProcessing = false
                }
            }
        }
    }

    private enum PasteboardValue {
        case data(Data)
        case string(String)
        case plist(Data)
    }

    private typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: PasteboardValue]]

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        guard let items = pasteboard.pasteboardItems else {
            return []
        }

        var snapshot: PasteboardSnapshot = []
        snapshot.reserveCapacity(items.count)

        for item in items {
            var dict: [NSPasteboard.PasteboardType: PasteboardValue] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = .data(data)
                    continue
                }
                if let string = item.string(forType: type) {
                    dict[type] = .string(string)
                    continue
                }
                if let plist = item.propertyList(forType: type),
                   let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                    dict[type] = .plist(data)
                    continue
                }
            }
            snapshot.append(dict)
        }

        return snapshot
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else {
            return
        }

        var items: [NSPasteboardItem] = []
        items.reserveCapacity(snapshot.count)

        for dict in snapshot {
            let item = NSPasteboardItem()
            for (type, value) in dict {
                switch value {
                case .data(let data):
                    item.setData(data, forType: type)
                case .string(let string):
                    item.setString(string, forType: type)
                case .plist(let data):
                    if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                        item.setPropertyList(plist, forType: type)
                    }
                }
            }
            items.append(item)
        }

        pasteboard.writeObjects(items)
    }

    private func getSelectedRichText() -> RichTextPayload? {
        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedElementValue: AnyObject?
        let focusedElementResult = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)

        let element: AXUIElement?
        if focusedElementResult == .success, let focused = focusedElementValue as! AXUIElement? {
            element = focused
        } else {
            var focusedApp: AnyObject?
            let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &focusedApp)
            guard result == .success, let app = focusedApp as! AXUIElement? else {
                return nil
            }

            var focusedWindow: AnyObject?
            let windowResult = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow)
            guard windowResult == .success, let window = focusedWindow as! AXUIElement? else {
                return nil
            }

            element = window
        }

        guard let element else {
            return nil
        }

        let attributedAttribute = "AXSelectedTextAttributedString" as CFString
        var attributedValue: AnyObject?
        let attributedResult = AXUIElementCopyAttributeValue(element, attributedAttribute, &attributedValue)
        if attributedResult == .success, let attributed = attributedValue as? NSAttributedString, !attributed.string.isEmpty {
            let html = RichTextConverter.html(from: attributed)
            let rtf = RichTextConverter.rtf(from: attributed)
            return RichTextPayload(plain: attributed.string, html: html, rtf: rtf)
        }

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            return RichTextPayload(plain: text, html: nil, rtf: nil)
        }

        return nil
    }
    
    func stopMonitoring() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
    }
}
