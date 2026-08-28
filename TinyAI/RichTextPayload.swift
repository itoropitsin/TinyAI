import AppKit
import Foundation
import ApplicationServices

final class TextReplacementTarget: @unchecked Sendable {
    let element: AXUIElement
    let processIdentifier: pid_t

    init(element: AXUIElement, processIdentifier: pid_t) {
        self.element = element
        self.processIdentifier = processIdentifier
    }
}

struct RichTextPayload: Equatable, @unchecked Sendable {
    var plain: String
    var html: String?
    var rtf: Data?
    var replacementTarget: TextReplacementTarget?

    init(plain: String, html: String?, rtf: Data?, replacementTarget: TextReplacementTarget? = nil) {
        self.plain = plain
        self.html = html
        self.rtf = rtf
        self.replacementTarget = replacementTarget
    }

    static func == (lhs: RichTextPayload, rhs: RichTextPayload) -> Bool {
        lhs.plain == rhs.plain && lhs.html == rhs.html && lhs.rtf == rhs.rtf
    }
}

enum RichTextHTMLSanitizer {
    static func sanitize(_ html: String) -> String {
        var result = html
        // List markers copied from rich-text applications can be duplicated:
        // once by the list structure and once as a literal character in the
        // text. Remove those characters before stripping the source font; some
        // applications use a private-use glyph for the visible marker.
        result = removeDuplicateListBullets(from: result)
        result = replaceStandalonePrivateUseListMarkers(from: result)
        result = stripFontMarkupAndStyles(from: result)
        return result
    }

    static func isLikelyHTML(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("<"), trimmed.contains(">") else { return false }
        let lowered = trimmed.prefix(512).lowercased()
        return lowered.contains("<p") || lowered.contains("<div") || lowered.contains("<span") || lowered.contains("<ul") || lowered.contains("<ol") || lowered.contains("<li") || lowered.contains("<br")
    }

    private static func stripFontMarkupAndStyles(from html: String) -> String {
        var result = html

        result = replacingRegex(in: result, pattern: "</?font\\b[^>]*>", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "\\sface\\s*=\\s*\"[^\"]*\"", with: "", options: [.caseInsensitive])

        // Strip CSS declarations that force non-system fonts/sizes while keeping other inline styles.
        result = replacingRegex(in: result, pattern: "font-family\\s*:\\s*[^;\"']+;?", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "font-size\\s*:\\s*[^;\"']+;?", with: "", options: [.caseInsensitive])

        // Clean up empty style="" attributes left after stripping.
        result = replacingRegex(in: result, pattern: "\\sstyle\\s*=\\s*\"\\s*\"", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "\\sstyle\\s*=\\s*\"\\s*;\\s*\"", with: "", options: [.caseInsensitive])

        return result
    }

    private static func removeDuplicateListBullets(from html: String) -> String {
        var result = html

        let markerPattern = "(?:&bull;|&#8226;|&#x2022;|•|·|◦|▪|‣|\\-|\\*|\\+|\(RichTextListMarkers.slackPrivateUseBullet)|&#58630;|&#x[eE]506;)"

        // Remove a literal bullet that appears inside <li> content (often duplicated by list styling).
        // Covers cases like:
        // - <li>• text</li>
        // - <li><p>• text</p></li>
        // - <li><span>•</span> text</li>
        // - <li><span><b>•</b></span> text</li>
        result = replacingRegex(
            in: result,
            pattern: "(<li\\b[^>]*>(?:(?!<(?:pre|code)\\b)(?:\\s|&nbsp;|<[^>]+>))*)(" + markerPattern + ")((?:</?[^>]+>)*)(?:[ \\t]|&nbsp;)+((?:</?[^>]+>)*)",
            with: "$1$3$4",
            options: [.caseInsensitive]
        )

        // Clean up empty wrappers that may remain after removing the bullet glyph.
        // Run this more than once so nested wrappers are removed from the inside out.
        let emptyInlineWrapperPattern = "<(?:strong|b|span|em|i|u|s|del|a)\\b[^>]*>\\s*</(?:strong|b|span|em|i|u|s|del|a)>"
        for _ in 0..<3 {
            result = replacingRegex(in: result, pattern: emptyInlineWrapperPattern, with: "", options: [.caseInsensitive])
        }

        return result
    }

    private static func replaceStandalonePrivateUseListMarkers(from html: String) -> String {
        let markerPattern = "(?:\(RichTextListMarkers.slackPrivateUseBullet)|&#58630;|&#x[eE]506;)"

        // A private-use list glyph outside <li> still carries list meaning.
        // Replace it with a normal bullet only at the start of a block. The
        // look-ahead allows inline wrappers such as <span>...</span> between
        // the glyph and the following whitespace.
        let blockStartPattern = "((?:^|<(?:p|div|h[1-6]|blockquote|td|th)\\b[^>]*>)(?:(?!<(?:pre|code)\\b)(?:\\s|&nbsp;|<[^>]+>))*)"
        let followingWhitespace = "(?=(?:(?:</?[^>]+>)*)(?:[ \\t]|&nbsp;))"
        return replacingRegex(
            in: html,
            pattern: blockStartPattern + markerPattern + followingWhitespace,
            with: "$1•",
            options: [.caseInsensitive]
        )
    }

    private static func replacingRegex(in input: String, pattern: String, with replacement: String, options: NSRegularExpression.Options = []) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: replacement)
    }
}

extension String {
    func normalizedPlainText() -> String {
        self
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }
}

enum RichTextListMarkers {
    static let slackPrivateUseBullet = "\u{E506}"

    enum Kind {
        case unordered
        case ordered
    }

    struct Match {
        let kind: Kind
        let markerRange: Range<String.Index>
        let separatorRange: Range<String.Index>
        let marker: Character
    }

    private static let unorderedCharacters: Set<Character> = ["•", "·", "◦", "▪", "‣", "-", "*", "+", "\u{E506}"]

    static func match(in line: String) -> Match? {
        var index = line.startIndex
        while index < line.endIndex, isHorizontalWhitespace(line[index]) {
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return nil }

        let marker = line[index]
        if unorderedCharacters.contains(marker) {
            let afterMarker = line.index(after: index)
            guard afterMarker < line.endIndex, isHorizontalWhitespace(line[afterMarker]) else {
                return nil
            }

            let separatorEnd = endOfHorizontalWhitespace(in: line, from: afterMarker)
            return Match(
                kind: .unordered,
                markerRange: index..<afterMarker,
                separatorRange: afterMarker..<separatorEnd,
                marker: marker
            )
        }

        if marker.isNumber || marker.isLetter {
            var cursor = line.index(after: index)
            var digitOrLetterCount = 1
            while cursor < line.endIndex,
                  digitOrLetterCount < 3,
                  line[cursor].isNumber == marker.isNumber,
                  line[cursor].isLetter == marker.isLetter {
                cursor = line.index(after: cursor)
                digitOrLetterCount += 1
            }

            if cursor < line.endIndex, line[cursor] == "." || line[cursor] == ")" {
                cursor = line.index(after: cursor)
            }
            guard cursor < line.endIndex, isHorizontalWhitespace(line[cursor]) else {
                return nil
            }

            let separatorEnd = endOfHorizontalWhitespace(in: line, from: cursor)
            return Match(
                kind: .ordered,
                markerRange: index..<cursor,
                separatorRange: cursor..<separatorEnd,
                marker: marker
            )
        }

        return nil
    }

    static func normalizedMarkdownLine(_ line: String, replacingPrivateUseMarker: Bool = true) -> String? {
        guard let match = match(in: line), match.kind == .unordered else {
            return nil
        }
        if !replacingPrivateUseMarker, match.marker == "\u{E506}" {
            return nil
        }

        let indent = String(line[..<match.markerRange.lowerBound])
        let rest = String(line[match.separatorRange.upperBound...])
        return indent + "- " + rest
    }

    static func displayMarkdownLine(_ line: String) -> String? {
        guard let match = match(in: line), match.kind == .unordered else {
            return nil
        }

        let indent = String(line[..<match.markerRange.lowerBound])
        let rest = String(line[match.separatorRange.upperBound...])
        return indent + "• " + rest
    }

    static func markerRange(in paragraph: String) -> NSRange? {
        guard let match = match(in: paragraph) else { return nil }
        return NSRange(match.markerRange, in: paragraph)
    }

    static func isCodeFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\u{00A0}"
    }

    private static func endOfHorizontalWhitespace(in line: String, from start: String.Index) -> String.Index {
        var index = start
        while index < line.endIndex, isHorizontalWhitespace(line[index]) {
            index = line.index(after: index)
        }
        return index
    }
}

enum RichTextConverter {
    static func attributedString(from payload: RichTextPayload) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let baseColor = NSColor.labelColor

        if let rtf = payload.rtf,
           let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            let normalizedPrivateUseMarkers = replacingPrivateUseListMarkers(in: attributed)
            let normalized = normalizedListMarkers(in: normalizedPrivateUseMarkers)
            let normalizedFonts = normalizedFonts(in: normalized, baseFont: baseFont)
            return applyingBaseAttributesIfMissing(to: normalizedFonts, baseFont: baseFont, baseColor: baseColor)
        }

        if let html = payload.html,
           let sanitizedHTML = RichTextHTMLSanitizer.sanitize(html).data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: sanitizedHTML,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
                .defaultAttributes: [
                    NSAttributedString.Key.font: baseFont,
                    NSAttributedString.Key.foregroundColor: baseColor
                ]
            ],
            documentAttributes: nil
           ) {
            // The HTML sanitizer has already handled every list-position
            // private-use marker. Leave any remaining marker untouched so
            // code blocks (for example <pre>...</pre>) remain verbatim.
            let normalized = normalizedListMarkers(in: attributed)
            let normalizedFonts = normalizedFonts(in: normalized, baseFont: baseFont)
            return applyingBaseAttributesIfMissing(to: normalizedFonts, baseFont: baseFont, baseColor: baseColor)
        }

        return attributedString(fromMarkdown: payload.plain.normalizedPlainText())
    }

    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let normalized = normalizedMarkdown(markdown)
        let trimmedNewlines = normalized.trimmingCharacters(in: .newlines)
        guard !trimmedNewlines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NSAttributedString(string: "")
        }

        let baseFont = NSFont.preferredFont(forTextStyle: .body)
        let baseColor = NSColor.labelColor

        guard #available(macOS 12.0, *) else {
            return NSAttributedString(string: trimmedNewlines, attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ])
        }

        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            options.failurePolicy = .returnPartiallyParsedIfPossible
            let prepared = preparedMarkdownForDisplay(trimmedNewlines)
            let attributed = try AttributedString(markdown: prepared, options: options)
            let attributedString = NSAttributedString(attributed)
            let normalizedMarkers = normalizedListMarkers(in: attributedString)
            let normalizedFonts = normalizedFonts(in: normalizedMarkers, baseFont: baseFont)
            return applyingBaseAttributesIfMissing(to: normalizedFonts, baseFont: baseFont, baseColor: baseColor)
        } catch {
            return NSAttributedString(string: trimmedNewlines, attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ])
        }
    }

    static func payload(fromMarkdown markdown: String) -> RichTextPayload {
        let normalized = normalizedMarkdown(markdown)
        let trimmedNewlines = normalized.trimmingCharacters(in: .newlines)
        guard !trimmedNewlines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RichTextPayload(plain: "", html: nil, rtf: nil)
        }

        let finalized = attributedString(fromMarkdown: trimmedNewlines)
        return RichTextPayload(
            plain: finalized.string.normalizedPlainText(),
            html: html(from: finalized),
            rtf: rtf(from: finalized)
        )
    }

    static func normalizedMarkdown(_ raw: String, replacingPrivateUseMarkers: Bool = true) -> String {
        let normalizedNewlines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        lines.reserveCapacity(normalizedNewlines.count / 20)
        var isInsideCodeFence = false

        for line in normalizedNewlines.components(separatedBy: "\n") {
            if RichTextListMarkers.isCodeFence(line) {
                lines.append(line)
                isInsideCodeFence.toggle()
                continue
            }

            if !isInsideCodeFence,
               let converted = RichTextListMarkers.normalizedMarkdownLine(
                   line,
                   replacingPrivateUseMarker: replacingPrivateUseMarkers
               ) {
                lines.append(converted)
            } else {
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func preparedMarkdownForDisplay(_ raw: String) -> String {
        var lines: [String] = []
        lines.reserveCapacity(raw.count / 20)
        var isInsideCodeFence = false

        for line in raw.components(separatedBy: "\n") {
            if RichTextListMarkers.isCodeFence(line) {
                lines.append(line)
                isInsideCodeFence.toggle()
                continue
            }

            if !isInsideCodeFence,
               let converted = RichTextListMarkers.displayMarkdownLine(line) {
                lines.append(converted)
            } else {
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func normalizedListMarkers(in attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }

        let mutable = NSMutableAttributedString(attributedString: attributed)
        let bulletPattern = "^(?:[\\s\\u00A0]*)(?:[•·◦▪‣\\-*+])(?:[\\s\\u00A0]+)"
        let orderedPattern = "^(?:[\\s\\u00A0]*)(?:(?:\\(?\\d{1,3}[\\).])|(?:\\d{1,3})|(?:[A-Za-z][\\).]))(?:[\\s\\u00A0]+)"
        let bulletRegex = try? NSRegularExpression(pattern: bulletPattern, options: [])
        let orderedRegex = try? NSRegularExpression(pattern: orderedPattern, options: [])

        var rangesToDelete: [NSRange] = []
        var location = 0
        while location < mutable.length {
            let currentString = mutable.string as NSString
            let paragraphRange = currentString.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraphRange)

            guard paragraphRange.length > 0 else { continue }
            guard let paragraphStyle = mutable.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle else {
                continue
            }
            guard !paragraphStyle.textLists.isEmpty else { continue }

            // Remove duplicated literal markers that were copied into the content (e.g. "1. " inside an <ol><li>).
            let paragraphText = currentString.substring(with: paragraphRange) as NSString
            let localRange = NSRange(location: 0, length: paragraphText.length)

            let match = bulletRegex?.firstMatch(in: paragraphText as String, options: [], range: localRange)
                ?? orderedRegex?.firstMatch(in: paragraphText as String, options: [], range: localRange)

            guard let match, match.range.length > 0 else { continue }

            rangesToDelete.append(NSRange(location: paragraphRange.location + match.range.location, length: match.range.length))
        }

        for range in rangesToDelete.reversed() {
            mutable.deleteCharacters(in: range)
        }

        return mutable
    }

    private static func replacingPrivateUseListMarkers(in attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }

        let mutable = NSMutableAttributedString(attributedString: attributed)
        var replacements: [NSRange] = []
        var location = 0

        while location < mutable.length {
            let currentString = mutable.string as NSString
            let paragraphRange = currentString.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraphRange)

            guard paragraphRange.length > 0 else { continue }
            let paragraphText = currentString.substring(with: paragraphRange)
            guard let markerRange = RichTextListMarkers.markerRange(in: paragraphText),
                  (paragraphText as NSString).substring(with: markerRange) == RichTextListMarkers.slackPrivateUseBullet else {
                continue
            }

            let absoluteMarkerLocation = paragraphRange.location + markerRange.location
            if let font = mutable.attribute(.font, at: absoluteMarkerLocation, effectiveRange: nil) as? NSFont,
               font.fontDescriptor.symbolicTraits.contains(.monoSpace) {
                // A monospaced paragraph is the usual RTF representation of a
                // code block. Preserve its contents, including a private-use
                // character that may be intentional code data.
                continue
            }

            replacements.append(NSRange(location: absoluteMarkerLocation, length: markerRange.length))
        }

        for range in replacements.reversed() {
            mutable.replaceCharacters(in: range, with: "•")
        }
        return mutable
    }

    private static func normalizedFonts(in attributed: NSAttributedString, baseFont: NSFont) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let mutable = NSMutableAttributedString(attributedString: attributed)

        let fontManager = NSFontManager.shared
        mutable.beginEditing()
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let replacement: NSFont
            if let font = value as? NSFont {
                let traits = fontManager.traits(of: font)
                let size = font.pointSize
                let systemWeight = systemWeight(from: fontManager.weight(of: font))
                let symbolicTraits = font.fontDescriptor.symbolicTraits
                let wantsMono = symbolicTraits.contains(.monoSpace)

                var candidate: NSFont
                if wantsMono {
                    candidate = NSFont.monospacedSystemFont(ofSize: size, weight: systemWeight)
                } else if traits.contains(.boldFontMask) {
                    candidate = NSFont.systemFont(ofSize: size, weight: .bold)
                } else {
                    candidate = NSFont.systemFont(ofSize: size, weight: systemWeight)
                }

                if traits.contains(.italicFontMask) {
                    candidate = fontManager.convert(candidate, toHaveTrait: .italicFontMask)
                }

                replacement = candidate
            } else {
                replacement = baseFont
            }

            mutable.addAttribute(.font, value: replacement, range: range)
        }
        mutable.endEditing()

        return mutable
    }

    private static func systemWeight(from fontManagerWeight: Int) -> NSFont.Weight {
        switch fontManagerWeight {
        case ..<(-6):
            return .ultraLight
        case -6 ... -4:
            return .thin
        case -3 ... -1:
            return .light
        case 0 ... 1:
            return .regular
        case 2 ... 3:
            return .medium
        case 4 ... 5:
            return .semibold
        case 6 ... 7:
            return .bold
        default:
            return .heavy
        }
    }

    private static func applyingBaseAttributesIfMissing(to attributed: NSAttributedString, baseFont: NSFont, baseColor: NSColor) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let mutable = NSMutableAttributedString(attributedString: attributed)

        mutable.beginEditing()
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: baseFont, range: range)
            }
        }
        mutable.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: baseColor, range: range)
            }
        }
        mutable.endEditing()

        return mutable
    }

    static func html(from attributed: NSAttributedString) -> String? {
        guard let data = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
        ) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func rtf(from attributed: NSAttributedString) -> Data? {
        try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func plain(fromHTML html: String) -> String {
        let sanitizedHTML = RichTextHTMLSanitizer.sanitize(html)
        guard let data = sanitizedHTML.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              )
        else {
            return html
        }

        return normalizedMarkdown(
            attributed.string.normalizedPlainText(),
            replacingPrivateUseMarkers: false
        )
    }
}

enum RichTextPasteboard {
    static func read(from pasteboard: NSPasteboard) -> RichTextPayload? {
        let rtf = pasteboard.data(forType: .rtf)
        let rawHTML = pasteboard.string(forType: .html)
            ?? pasteboard.data(forType: .html).flatMap { String(data: $0, encoding: .utf8) }
        let html = rawHTML.map(RichTextHTMLSanitizer.sanitize)

        let plain: String
        if let plainString = pasteboard.string(forType: .string) {
            plain = RichTextConverter.normalizedMarkdown(plainString.normalizedPlainText())
        } else if let html {
            plain = RichTextConverter.plain(fromHTML: html)
        } else if let rtf,
                  let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            let payload = RichTextPayload(plain: attributed.string, html: nil, rtf: rtf)
            let normalizedAttributed = RichTextConverter.attributedString(from: payload)
            plain = RichTextConverter.normalizedMarkdown(
                normalizedAttributed.string.normalizedPlainText(),
                replacingPrivateUseMarkers: false
            )
        } else {
            return nil
        }

        return RichTextPayload(plain: plain, html: html, rtf: rtf)
    }

    static func write(_ payload: RichTextPayload, to pasteboard: NSPasteboard) {
        let attributed: NSAttributedString? = (payload.rtf == nil || payload.html == nil)
            ? RichTextConverter.attributedString(from: payload)
            : nil
        let rtf = payload.rtf ?? attributed.flatMap(RichTextConverter.rtf(from:))
        let html = payload.html.map(RichTextHTMLSanitizer.sanitize) ?? attributed.flatMap(RichTextConverter.html(from:))

        pasteboard.clearContents()

        if let rtf {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let html, let data = html.data(using: .utf8) {
            pasteboard.setData(data, forType: .html)
        }

        pasteboard.setString(RichTextConverter.normalizedMarkdown(payload.plain), forType: .string)
    }
}
