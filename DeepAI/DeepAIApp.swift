import SwiftUI
import AppKit

@main
struct DeepAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var translationService = TranslationService()
    @StateObject private var keyboardMonitor = KeyboardMonitor()
    
    var body: some Scene {
        WindowGroup {
            MainTranslationView()
                .environmentObject(translationService)
                .environmentObject(keyboardMonitor)
                .onAppear {
                    appDelegate.translationService = translationService
                    keyboardMonitor.onDoubleCommandC = { [weak appDelegate] selectedText in
                        appDelegate?.showTranslationPopup(with: selectedText)
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var popupWindow: NSWindow?
    weak var translationService: TranslationService?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Не скрываем приложение из dock, чтобы было видно основное окно
        // NSApp.setActivationPolicy(.accessory)
        
        // Запрашиваем разрешение на доступность
        requestAccessibilityPermission()
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            print("Требуется разрешение на доступность для работы глобальных горячих клавиш")
        }
    }
    
    
    func showTranslationPopup(with text: String) {
        // Убеждаемся, что все выполняется на главном потоке
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let translationService = self.translationService else { return }
            
            // Закрываем предыдущее окно, если оно открыто
            if let existingWindow = self.popupWindow {
                existingWindow.close()
                self.popupWindow = nil
            }
            
            // ВАЖНО: Временно активируем приложение на текущем desktop
            // Это гарантирует, что новое окно будет создано на том же desktop
            // где находится активное приложение
            let wasActive = NSApplication.shared.isActive
            if !wasActive {
                // Активируем приложение мягко, чтобы перейти на текущий desktop
                NSApp.activate(ignoringOtherApps: true)
                // Небольшая задержка для перехода на правильный desktop
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.createPopupWindow(text: text, translationService: translationService)
                }
            } else {
                self.createPopupWindow(text: text, translationService: translationService)
            }
        }
    }
    
    private func createPopupWindow(text: String, translationService: TranslationService) {
        // Создаем view на главном потоке
        let popupView = TranslationPopupView(selectedText: text, onClose: { [weak self] in
            DispatchQueue.main.async {
                self?.popupWindow?.close()
                self?.popupWindow = nil
            }
        })
        .environmentObject(translationService)
        
        // Создаем hosting view с правильными размерами
        let hostingView = NSHostingView(rootView: popupView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        
        // Создаем окно с возможностью перетаскивания
        let window = DraggableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [NSWindow.StyleMask.borderless, NSWindow.StyleMask.fullSizeContentView],
            backing: NSWindow.BackingStoreType.buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        
        // Используем правильные настройки для работы на том же desktop
        // fullScreenAuxiliary позволяет окну появляться в полноэкранном режиме
        // НЕ используем canJoinAllSpaces - это делает окно видимым на всех spaces
        // НЕ используем moveToActiveSpace - это переносит окно
        // Используем только fullScreenAuxiliary для полноэкранного режима
        window.collectionBehavior = [.fullScreenAuxiliary]
        
        // Делаем окно перемещаемым через заголовок
        window.isMovableByWindowBackground = false
        
        // Получаем активный экран для правильного позиционирования
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen.main!
        
        let screenFrame = screen.frame
        let windowX = mouseLocation.x - 200
        let windowY = mouseLocation.y - 200
        
        // Убеждаемся, что окно не выходит за границы экрана
        let constrainedX = max(screenFrame.minX, min(windowX, screenFrame.maxX - 400))
        let constrainedY = max(screenFrame.minY, min(windowY, screenFrame.maxY - 400))
        
        window.setFrameOrigin(NSPoint(x: constrainedX, y: constrainedY))
        
        // Показываем окно БЕЗ активации приложения
        // Используем orderFront вместо makeKeyAndOrderFront, чтобы не активировать приложение
        // Это гарантирует, что окно останется на том же desktop, где находится активное приложение
        window.orderFront(nil)
        
        self.popupWindow = window
    }
}

