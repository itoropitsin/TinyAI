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
            do {
                var options = AttributedString.MarkdownParsingOptions()
                options.interpretedSyntax = .inlineOnlyPreservingWhitespace
                options.failurePolicy = .returnPartiallyParsedIfPossible
                let prepared = preparedMarkdown(content)
                let attributed = try AttributedString(markdown: prepared, options: options)
                textView.textStorage?.setAttributedString(normalizedMarkdownFonts(NSAttributedString(attributed)))
            } catch {
                textView.textStorage?.setAttributedString(NSAttributedString(string: content))
            }
        } else {
            textView.textStorage?.setAttributedString(NSAttributedString(string: content))
        }
    }

    private func preparedMarkdown(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func normalizedMarkdownFonts(_ attributed: NSAttributedString) -> NSAttributedString {
        let normalized = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: normalized.length)
        normalized.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let font = value as? NSFont
            normalized.addAttribute(.font, value: normalizedFont(from: font), range: range)
        }
        return normalized
    }

    private func normalizedFont(from original: NSFont?) -> NSFont {
        let originalFont = original ?? baseFont
        let traits = originalFont.fontDescriptor.symbolicTraits
        let isMonospaced = traits.contains(.monoSpace)
        let isBold = traits.contains(.bold)
        let isItalic = traits.contains(.italic)

        let pointSize = originalFont.pointSize > 0 ? originalFont.pointSize : baseFont.pointSize
        let weight: NSFont.Weight = isBold ? .semibold : .regular

        var font: NSFont
        if isMonospaced {
            font = NSFont.monospacedSystemFont(ofSize: pointSize, weight: weight)
        } else {
            font = NSFont.systemFont(ofSize: pointSize, weight: weight)
        }

        if isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        return font
    }

    final class Coordinator {
        var lastContent: String?
        var lastWasPlaceholder: Bool = false
    }
}
