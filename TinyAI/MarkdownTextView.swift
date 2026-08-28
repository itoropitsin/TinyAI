import SwiftUI
import AppKit
import Foundation

struct MarkdownTextView: NSViewRepresentable {
    let markdown: String
    let placeholder: String

    private var baseFont: NSFont {
        NSFont.preferredFont(forTextStyle: .body)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.font = baseFont
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let isPlaceholder = markdown.isEmpty
        let content = isPlaceholder ? placeholder : markdown

        if context.coordinator.lastContent == content, context.coordinator.lastWasPlaceholder == isPlaceholder {
            return
        }
        context.coordinator.lastContent = content
        context.coordinator.lastWasPlaceholder = isPlaceholder

        if isPlaceholder {
            textView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: content,
                    attributes: [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .font: baseFont
                    ]
                )
            )
            return
        }

        if #available(macOS 12.0, *) {
            textView.textStorage?.setAttributedString(RichTextConverter.attributedString(fromMarkdown: content))
        } else {
            textView.textStorage?.setAttributedString(NSAttributedString(string: RichTextConverter.normalizedMarkdown(content)))
        }
    }

    final class Coordinator {
        var lastContent: String?
        var lastWasPlaceholder: Bool = false
    }
}
