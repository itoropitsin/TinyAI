import AppKit

class DraggableWindow: NSPanel {
    private var isDragging = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private let resizeEdgeMargin: CGFloat = 8

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
        let isNearResizeEdge =
            location.x <= resizeEdgeMargin
            || location.x >= (frame.width - resizeEdgeMargin)
            || location.y <= resizeEdgeMargin
            || location.y >= (frame.height - resizeEdgeMargin)

        // Check whether the click is within the header area (top 50px)
        if !isNearResizeEdge, location.y > (frame.height - 50) {
            isDragging = true
            dragStartMouseLocation = NSEvent.mouseLocation
            dragStartWindowOrigin = frame.origin
        }
        super.mouseDown(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isDragging {
            let currentMouseLocation = NSEvent.mouseLocation
            let deltaX = currentMouseLocation.x - dragStartMouseLocation.x
            let deltaY = currentMouseLocation.y - dragStartMouseLocation.y
            setFrameOrigin(NSPoint(
                x: dragStartWindowOrigin.x + deltaX,
                y: dragStartWindowOrigin.y + deltaY
            ))
        } else {
            super.mouseDragged(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        super.mouseUp(with: event)
    }
}
