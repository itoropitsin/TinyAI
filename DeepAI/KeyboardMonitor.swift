import Cocoa
import Carbon
import ApplicationServices
import Combine

class KeyboardMonitor: ObservableObject {
    var onDoubleCommandC: ((String) -> Void)?
    
    private var lastCommandCPressTime: Date?
    private let doublePressInterval: TimeInterval = 0.5
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isProcessing: Bool = false // Защита от множественных срабатываний
    
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
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            
            // Проверяем Command-C
            if keyCode == 8 && flags.contains(.maskCommand) { // 8 = C key
                let now = Date()
                
                if let lastPress = lastCommandCPressTime,
                   now.timeIntervalSince(lastPress) < doublePressInterval {
                    // Двойное нажатие обнаружено
                    // Проверяем, не обрабатывается ли уже запрос
                    if !isProcessing {
                        isProcessing = true
                        // Вызываем на главном потоке
                        DispatchQueue.main.async { [weak self] in
                            self?.handleDoubleCommandC()
                        }
                    }
                    // Поглощаем событие, чтобы не копировалось
                    return nil
                }
                
                lastCommandCPressTime = now
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleDoubleCommandC() {
        // Убеждаемся, что мы на главном потоке
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleDoubleCommandC()
            }
            return
        }
        
        // Получаем выделенный текст через Accessibility API
        // Пробуем получить выделенный текст через Accessibility
        if let selectedText = getSelectedText(), !selectedText.isEmpty {
            onDoubleCommandC?(selectedText)
            // Сбрасываем флаг после небольшой задержки
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.isProcessing = false
            }
        } else {
            // Fallback: используем буфер обмена
            let pasteboard = NSPasteboard.general
            let previousContents = pasteboard.string(forType: .string)
            
            // Копируем выделенный текст
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C key
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            
            // Небольшая задержка для копирования
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                let selectedText = pasteboard.string(forType: .string) ?? ""
                if !selectedText.isEmpty {
                    DispatchQueue.main.async {
                        self.onDoubleCommandC?(selectedText)
                    }
                }
                // Восстанавливаем предыдущее содержимое буфера обмена
                if let previous = previousContents {
                    pasteboard.setString(previous, forType: .string)
                }
                // Сбрасываем флаг после обработки
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func getSelectedText() -> String? {
        // Получаем системное приложение
        let systemWideElement = AXUIElementCreateSystemWide()
        
        // Получаем фокусное приложение
        var focusedApp: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        
        guard result == .success, let app = focusedApp as! AXUIElement? else {
            return nil
        }
        
        // Получаем фокусное окно
        var focusedWindow: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard windowResult == .success, let window = focusedWindow as! AXUIElement? else {
            return nil
        }
        
        // Получаем выделенный текст
        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(window, kAXSelectedTextAttribute as CFString, &selectedText)
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
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

