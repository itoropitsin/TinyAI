import Cocoa
import Carbon
import ApplicationServices
import Combine

class KeyboardMonitor: ObservableObject {
    var onDoubleCommandC: ((RichTextPayload) -> Void)?
    @Published var isCustomActionHotkeysEnabled: Bool = false
    @Published var customActionHotkey: Int?
    
    private var lastCommandCPressTime: Date?
    private let doublePressInterval: TimeInterval = 0.5
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isProcessing: Bool = false // Protection against multiple triggers
    private var isProcessingCustomAction: Bool = false
    private var isSimulatingCopy: Bool = false
    private var setupRetryCount: Int = 0
    private let setupRetryLimit: Int = 10
    
    init() {
        setupGlobalHotkey()
    }
    
    deinit {
        stopMonitoring()
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
            print("Failed to create event tap")
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

            if isCustomActionHotkeysEnabled && flags.contains(.maskCommand) {
                let mapping: [Int64: Int] = [
                    18: 1, // 1
                    19: 2, // 2
                    20: 3, // 3
                    21: 4, // 4
                    23: 5  // 5
                ]

                if let index = mapping[keyCode], !isProcessingCustomAction {
                    isProcessingCustomAction = true
                    DispatchQueue.main.async { [weak self] in
                        self?.customActionHotkey = index
                        DispatchQueue.main.async {
                            self?.customActionHotkey = nil
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.isProcessingCustomAction = false
                    }
                    return nil
                }
            }
            
            // Detect Command-C
            if keyCode == 8 && flags.contains(.maskCommand) { // 8 = C key
                let now = Date()
                
                if let lastPress = lastCommandCPressTime,
                   now.timeIntervalSince(lastPress) < doublePressInterval {
                    // Double press detected
                    // Check if a request is already being processed
                    if !isProcessing {
                        isProcessing = true
                        // Execute on the main thread
                        DispatchQueue.main.async { [weak self] in
                            self?.handleDoubleCommandC()
                        }
                    }
                    // Swallow the event so it doesn't copy
                    return nil
                }
                
                lastCommandCPressTime = now
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleDoubleCommandC() {
        // Ensure we are on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleDoubleCommandC()
            }
            return
        }
        
        if let payload = getSelectedRichText(), !payload.plain.isEmpty {
            onDoubleCommandC?(payload)
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
                        self.onDoubleCommandC?(payload)
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
        }
    }
}

