import AppKit

class DraggableWindow: NSPanel {
    private var isDragging = false
    private var dragStartLocation: NSPoint = .zero

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isFloatingPanel = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    override func mouseDown(with event: NSEvent) {
        let location = event.locationInWindow
        // Проверяем, кликнули ли в области заголовка (верхние 50 пикселей)
        if location.y > (frame.height - 50) {
            isDragging = true
            dragStartLocation = event.locationInWindow
        }
        super.mouseDown(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isDragging {
            let currentLocation = NSEvent.mouseLocation
            let newOrigin = NSPoint(
                x: currentLocation.x - dragStartLocation.x,
                y: currentLocation.y - (frame.height - dragStartLocation.y)
            )
            setFrameOrigin(newOrigin)
        } else {
            super.mouseDragged(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        super.mouseUp(with: event)
    }
}

