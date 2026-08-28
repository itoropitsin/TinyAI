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

/// The single, canonical representation used by the popup, Copy and Replace.
/// The attributed string is deliberately kept alongside the pasteboard payload:
/// reading our own RTF back would run the source-app normalisation a second time.
struct PreparedRichText: @unchecked Sendable {
    let plain: String
    let attributed: NSAttributedString
    let payload: RichTextPayload

    init(attributed: NSAttributedString, payload: RichTextPayload) {
        self.attributed = attributed
        self.plain = payload.plain
        self.payload = payload
    }
}

/// A semantic description of rich text.  It intentionally ignores fonts,
/// colours and exact translated character counts, while retaining the parts
/// that a built-in translation must not change.
struct RichTextStructureSignature: Equatable, Sendable {
    let blocks: [String]
    let links: [String]
    let inlineTraits: [String]
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
        return lowered.contains("<html") || lowered.contains("<body") || lowered.contains("<p") || lowered.contains("<div") || lowered.contains("<span") || lowered.contains("<ul") || lowered.contains("<ol") || lowered.contains("<li") || lowered.contains("<pre") || lowered.contains("<code") || lowered.contains("<a ") || lowered.contains("<strong") || lowered.contains("<em") || lowered.contains("<h1") || lowered.contains("<table") || lowered.contains("<tr") || lowered.contains("<td") || lowered.contains("<blockquote") || lowered.contains("<br")
    }

    private static func stripFontMarkupAndStyles(from html: String) -> String {
        var result = html

        // AppKit writes a document-level CSS block for every source font.  It
        // is presentation-only and can contain declarations that span lines;
        // remove the complete block before applying inline sanitisation so the
        // generated HTML remains valid.
        result = replacingRegex(
            in: result,
            pattern: "<style\\b[^>]*>.*?</style\\s*>",
            with: "",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        result = replacingRegex(in: result, pattern: "</?font\\b[^>]*>", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "\\sface\\s*=\\s*\"[^\"]*\"", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "\\scolor\\s*=\\s*\"[^\"]*\"", with: "", options: [.caseInsensitive])

        // Strip CSS declarations that carry source-app typography or colors
        // while keeping semantic styles such as bold and italic.
        result = replacingRegex(in: result, pattern: "font-family\\s*:\\s*[^;\"']+;?", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "font-size\\s*:\\s*[^;\"']+;?", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "(?<![-\\w])(?:background-)?color\\s*:\\s*[^;\"']+;?", with: "", options: [.caseInsensitive])

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
    private static let defaultFont = NSFont.preferredFont(forTextStyle: .body)
    private static let defaultColor = NSColor.labelColor

    private struct HTMLBlock {
        let depth: Int
        let kind: String
        let content: String
    }

    /// Prepare Markdown exactly once.  The resulting attributed string is the
    /// one shown in the UI; its HTML/RTF siblings are used for pasteboard I/O.
    static func prepare(markdown: String) -> PreparedRichText {
        let attributed = attributedString(fromMarkdown: markdown)
        return prepared(attributed: attributed)
    }

    /// Prepare a sanitized HTML response.  A non-HTML response is rejected so
    /// callers can use the Markdown/text fallback deliberately.
    static func prepare(html: String) -> PreparedRichText? {
        let sanitized = RichTextHTMLSanitizer.sanitize(html)
        guard RichTextHTMLSanitizer.isLikelyHTML(sanitized),
              let data = sanitized.data(using: .utf8),
              let parsed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                    .defaultAttributes: [
                        NSAttributedString.Key.font: defaultFont,
                        NSAttributedString.Key.foregroundColor: defaultColor
                    ]
                ],
                documentAttributes: nil
              ) else {
            return nil
        }

        let parsedWithoutSyntheticNewline = removingSyntheticFinalNewline(
            from: parsed,
            sourceHTML: sanitized
        )
        let withPrivateMarkers = replacingPrivateUseListMarkers(in: parsedWithoutSyntheticNewline)
        let withoutDuplicateMarkers = normalizedListMarkers(in: withPrivateMarkers)
        let withSemanticFonts = normalizedFonts(in: withoutDuplicateMarkers, baseFont: defaultFont)
        let canonical = applyingBaseAttributesIfMissing(
            to: normalizedColors(in: withSemanticFonts, baseColor: defaultColor),
            baseFont: defaultFont,
            baseColor: defaultColor
        )
        return prepared(attributed: canonical)
    }

    static func prepare(payload: RichTextPayload) -> PreparedRichText {
        if let html = payload.html, let prepared = prepare(html: html) {
            return prepared
        }
        if let rtf = payload.rtf,
           let parsed = try? NSAttributedString(
            data: rtf,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
           ) {
            let withPrivateMarkers = replacingPrivateUseListMarkers(in: parsed)
            let withoutDuplicateMarkers = normalizedListMarkers(in: withPrivateMarkers)
            let withSemanticFonts = normalizedFonts(in: withoutDuplicateMarkers, baseFont: defaultFont)
            let canonical = applyingBaseAttributesIfMissing(
                to: normalizedColors(in: withSemanticFonts, baseColor: defaultColor),
                baseFont: defaultFont,
                baseColor: defaultColor
            )
            return prepared(attributed: canonical)
        }
        return prepare(markdown: payload.plain.normalizedPlainText())
    }

    static func attributedString(from payload: RichTextPayload) -> NSAttributedString {
        prepare(payload: payload).attributed
    }

    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let normalized = normalizedMarkdown(markdown)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NSAttributedString(string: "")
        }

        let lines = normalized.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        var isInsideCodeFence = false
        var listStack: [NSTextList] = []

        for (index, line) in lines.enumerated() {
            let startsFence = RichTextListMarkers.isCodeFence(line)
            let lineStart = result.length

            if isInsideCodeFence || startsFence {
                listStack.removeAll()
                result.append(NSAttributedString(
                    string: line,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: defaultFont.pointSize, weight: .regular),
                        .foregroundColor: defaultColor
                    ]
                ))
            } else if let match = RichTextListMarkers.match(in: line) {
                let body = String(line[match.separatorRange.upperBound...])
                result.append(inlineAttributedString(body))
                let depth = listDepth(in: line, marker: match)
                if depth < listStack.count {
                    listStack.removeLast(listStack.count - depth)
                }
                if listStack.count == depth {
                    listStack.append(NSTextList(
                        markerFormat: match.kind == .ordered ? .decimal : .disc,
                        options: 0
                    ))
                } else if listStack[depth].markerFormat != (match.kind == .ordered ? .decimal : .disc) {
                    listStack.removeLast(listStack.count - depth)
                    listStack.append(NSTextList(
                        markerFormat: match.kind == .ordered ? .decimal : .disc,
                        options: 0
                    ))
                }
                applyListStyle(
                    to: result,
                    range: NSRange(location: lineStart, length: result.length - lineStart),
                    textLists: listStack,
                    depth: depth
                )
            } else {
                listStack.removeAll()
                result.append(inlineAttributedString(line))
            }

            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: defaultFont,
                    .foregroundColor: defaultColor
                ]))
                if let style = result.attribute(.paragraphStyle, at: lineStart, effectiveRange: nil) as? NSParagraphStyle {
                    result.addAttribute(
                        .paragraphStyle,
                        value: style,
                        range: NSRange(location: lineStart, length: result.length - lineStart)
                    )
                }
            }

            if startsFence {
                isInsideCodeFence.toggle()
            }
        }

        let withFonts = normalizedFonts(in: result, baseFont: defaultFont)
        return applyingBaseAttributesIfMissing(
            to: normalizedColors(in: withFonts, baseColor: defaultColor),
            baseFont: defaultFont,
            baseColor: defaultColor
        )
    }

    static func payload(fromMarkdown markdown: String) -> RichTextPayload {
        prepare(markdown: markdown).payload
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

    static func structureSignature(of attributed: NSAttributedString) -> RichTextStructureSignature {
        var blocks: [String] = []
        var location = 0
        while location < attributed.length {
            let paragraphRange = (attributed.string as NSString).paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            let contentLength = max(0, paragraphRange.length - (
                (attributed.string as NSString).substring(with: paragraphRange).hasSuffix("\n") ? 1 : 0
            ))
            let text = (attributed.string as NSString).substring(
                with: NSRange(location: paragraphRange.location, length: contentLength)
            )
            let style = attributed.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
            if let list = style?.textLists.last {
                let kind = list.markerFormat == .decimal ? "ordered" : "unordered"
                let depth = max(1, style?.textLists.count ?? 1)
                blocks.append("list:\(kind):\(depth):\(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "empty" : "item")")
            } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append("blank")
            } else {
                let isCode = attributed.attribute(.font, at: paragraphRange.location, effectiveRange: nil)
                    .flatMap { ($0 as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) } ?? false
                let block = isCode ? "code" : "paragraph"
                // Adjacent monospaced paragraphs are one code block for the
                // purpose of validation; AppKit may split or merge their line
                // ranges while round-tripping HTML/RTF.
                if block != "code" || blocks.last != "code" {
                    blocks.append(block)
                }
            }
            location = NSMaxRange(paragraphRange)
        }

        var links: [String] = []
        if attributed.length > 0 {
            attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length), options: []) { value, _, _ in
                guard let value else { return }
                if let url = value as? URL {
                    links.append(normalizedLink(url.absoluteString))
                } else if let url = value as? NSURL {
                    links.append(normalizedLink(url.absoluteString ?? url.description))
                } else {
                    links.append(String(describing: value))
                }
            }
        }

        var traitCounts: [String: Int] = [:]
        if attributed.length > 0 {
            attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length), options: []) { value, _, _ in
                guard let font = value as? NSFont else {
                    return
                }
                let traits = font.fontDescriptor.symbolicTraits
                var parts: [String] = []
                if traits.contains(.monoSpace) { parts.append("mono") }
                if traits.contains(.bold) { parts.append("bold") }
                if traits.contains(.italic) { parts.append("italic") }
                if !parts.isEmpty {
                    let key = parts.joined(separator: "+")
                    // Counts are intentionally presence flags.  AppKit may
                    // merge adjacent code paragraphs into one run when it
                    // parses the HTML again; that is not a structure change.
                    traitCounts[key] = 1
                }
            }
        }

        let inlineTraits = traitCounts.keys.sorted().map { "\($0):\(traitCounts[$0] ?? 0)" }
        return RichTextStructureSignature(blocks: blocks, links: links, inlineTraits: inlineTraits)
    }

    private static func normalizedLink(_ value: String) -> String {
        guard var components = URLComponents(string: value),
              components.host != nil,
              components.path == "/" else {
            return value
        }
        components.path = ""
        return components.string ?? value
    }

    static func html(from attributed: NSAttributedString) -> String? {
        guard attributed.length > 0 else { return nil }

        var blocks: [HTMLBlock] = []
        var location = 0
        while location < attributed.length {
            let paragraphRange = (attributed.string as NSString).paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            let rawParagraph = (attributed.string as NSString).substring(with: paragraphRange)
            let contentLength = max(0, paragraphRange.length - (rawParagraph.hasSuffix("\n") ? 1 : 0))
            let contentRange = NSRange(location: paragraphRange.location, length: contentLength)
            let style = attributed.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
            let list = style?.textLists.last
            let depth = max(0, (style?.textLists.count ?? 1) - 1)
            let kind = list?.markerFormat == .decimal ? "ol" : "ul"
            let isCode = isMonospacedParagraph(in: attributed, range: contentRange)
            let baseContent = isCode
                ? escapeHTML((attributed.string as NSString).substring(with: contentRange))
                : htmlInline(from: attributed, range: contentRange)
            let isEmpty = baseContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // HTML document parsing adds one final newline even when the
            // source has none. Encode a real terminal newline explicitly so
            // the parser can distinguish it from that synthetic character.
            let isTerminalBlock = NSMaxRange(paragraphRange) == attributed.length
                && rawParagraph.hasSuffix("\n")
            let content = isTerminalBlock && !isEmpty ? baseContent + "<br>" : baseContent

            if list != nil {
                blocks.append(HTMLBlock(depth: depth, kind: kind, content: content))
            } else if isCode {
                blocks.append(HTMLBlock(depth: -1, kind: "pre", content: content))
            } else if isEmpty {
                blocks.append(HTMLBlock(depth: -1, kind: "blank", content: ""))
            } else {
                blocks.append(HTMLBlock(depth: -1, kind: "p", content: content))
            }
            location = NSMaxRange(paragraphRange)
        }

        var body = ""
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            if block.depth >= 0 {
                body += renderHTMLList(blocks, index: &index, depth: block.depth, kind: block.kind)
            } else if block.kind == "pre" {
                var codeLines: [String] = []
                while index < blocks.count, blocks[index].kind == "pre" {
                    codeLines.append(blocks[index].content)
                    index += 1
                }
                body += "<pre><code>\(codeLines.joined(separator: "\n"))</code></pre>"
            } else if block.kind == "blank" {
                body += "<p><br></p>"
                index += 1
            } else {
                body += "<p>\(block.content)</p>"
                index += 1
            }
        }

        return "<html><body>\(body)</body></html>"
    }

    static func rtf(from attributed: NSAttributedString) -> Data? {
        try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func plain(fromHTML html: String) -> String {
        guard let plain = prepare(html: html)?.plain else { return html }
        // Keep this legacy helper's Markdown-compatible return value for
        // callers that explicitly ask for plain HTML extraction.  Prepared
        // payloads themselves retain visible bullets ("•") for pasteboard
        // fallbacks.
        return normalizedMarkdown(plain, replacingPrivateUseMarkers: false)
    }

    private static func prepared(attributed: NSAttributedString) -> PreparedRichText {
        let canonical = applyingBaseAttributesIfMissing(
            to: normalizedColors(in: normalizedFonts(in: attributed, baseFont: defaultFont), baseColor: defaultColor),
            baseFont: defaultFont,
            baseColor: defaultColor
        )
        let plain = plainText(from: canonical)
        let payload = RichTextPayload(
            plain: plain,
            html: canonical.length > 0 ? html(from: canonical) : nil,
            rtf: canonical.length > 0 ? rtf(from: canonical) : nil
        )
        return PreparedRichText(attributed: canonical, payload: payload)
    }

    private static func plainText(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }

        var result = ""
        var counters: [Int: Int] = [:]
        var location = 0
        while location < attributed.length {
            let paragraphRange = (attributed.string as NSString).paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            let paragraph = (attributed.string as NSString).substring(with: paragraphRange)
            let hasNewline = paragraph.hasSuffix("\n")
            let contentLength = max(0, paragraphRange.length - (hasNewline ? 1 : 0))
            let content = (paragraph as NSString).substring(with: NSRange(location: 0, length: contentLength))
            let style = attributed.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle

            if let list = style?.textLists.last {
                let depth = max(0, (style?.textLists.count ?? 1) - 1)
                for key in Array(counters.keys) where key > depth {
                    counters.removeValue(forKey: key)
                }
                let ordered = list.markerFormat == .decimal
                let number = counters[depth, default: 1]
                counters[depth] = ordered ? number + 1 : number
                let indent = String(repeating: "  ", count: depth)
                result += indent + (ordered ? "\(number). " : "• ") + content
            } else {
                counters.removeAll()
                result += content
            }

            if hasNewline {
                result += "\n"
            }
            location = NSMaxRange(paragraphRange)
        }

        return result.normalizedPlainText()
    }

    private static func renderHTMLList(_ blocks: [HTMLBlock], index: inout Int, depth: Int, kind: String) -> String {
        var result = "<\(kind)>"
        while index < blocks.count {
            let block = blocks[index]
            guard block.depth == depth, block.kind == kind else { break }
            result += "<li>\(block.content)"
            index += 1

            if index < blocks.count, blocks[index].depth > depth {
                let nested = blocks[index]
                result += renderHTMLList(blocks, index: &index, depth: depth + 1, kind: nested.kind)
            }
            result += "</li>"
        }
        result += "</\(kind)>"
        return result
    }

    private static func isMonospacedParagraph(in attributed: NSAttributedString, range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        var hasFont = false
        var allMono = true
        attributed.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
            hasFont = true
            guard let font = value as? NSFont else {
                allMono = false
                return
            }
            allMono = allMono && font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        return hasFont && allMono
    }

    private static func htmlInline(from attributed: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var result = ""
        attributed.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            let text = (attributed.string as NSString).substring(with: subrange)
            var value = escapeHTML(text)
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let link = attributes[.link].flatMap { value -> String? in
                if let url = value as? URL { return url.absoluteString }
                if let url = value as? NSURL { return url.absoluteString }
                return String(describing: value)
            }

            if traits.contains(.monoSpace) { value = "<code>\(value)</code>" }
            if traits.contains(.bold) { value = "<strong>\(value)</strong>" }
            if traits.contains(.italic) { value = "<em>\(value)</em>" }
            if let link {
                value = "<a href=\"\(escapeHTMLAttribute(link))\">\(value)</a>"
            }
            result += value
        }
        return result
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeHTMLAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func inlineAttributedString(_ markdown: String) -> NSAttributedString {
        guard #available(macOS 12.0, *) else {
            return NSAttributedString(string: markdown, attributes: [
                .font: defaultFont,
                .foregroundColor: defaultColor
            ])
        }

        do {
            let value = try AttributedString(markdown: markdown, options: {
                var options = AttributedString.MarkdownParsingOptions()
                options.interpretedSyntax = .inlineOnlyPreservingWhitespace
                options.failurePolicy = .returnPartiallyParsedIfPossible
                return options
            }())

            let result = NSMutableAttributedString(attributedString: NSAttributedString(value))
            for run in value.runs {
                let intent = run.inlinePresentationIntent
                let isCode = intent?.contains(.code) == true
                let isBold = intent?.contains(.stronglyEmphasized) == true
                let isItalic = intent?.contains(.emphasized) == true
                var font = isCode
                    ? NSFont.monospacedSystemFont(ofSize: defaultFont.pointSize, weight: isBold ? .bold : .regular)
                    : NSFont.systemFont(ofSize: defaultFont.pointSize, weight: isBold ? .bold : .regular)
                if isItalic {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                result.addAttribute(NSAttributedString.Key.font, value: font, range: NSRange(run.range, in: value))
            }

            return applyingBaseAttributesIfMissing(to: result, baseFont: defaultFont, baseColor: defaultColor)
        } catch {
            return NSAttributedString(string: markdown, attributes: [
                .font: defaultFont,
                .foregroundColor: defaultColor
            ])
        }
    }

    private static func listDepth(in line: String, marker: RichTextListMarkers.Match) -> Int {
        let prefix = line[..<marker.markerRange.lowerBound]
        let spaces = prefix.reduce(into: 0) { result, character in
            result += character == "\t" ? 2 : 1
        }
        return max(0, spaces / 2)
    }

    private static func applyListStyle(to attributed: NSMutableAttributedString, range: NSRange, textLists: [NSTextList], depth: Int) {
        guard range.length > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.textLists = textLists
        style.firstLineHeadIndent = CGFloat(depth * 20)
        style.headIndent = CGFloat((depth + 1) * 20)
        attributed.addAttribute(.paragraphStyle, value: style, range: range)
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

            guard paragraphRange.length > 0,
                  let paragraphStyle = mutable.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle,
                  !paragraphStyle.textLists.isEmpty else {
                continue
            }

            let paragraphText = currentString.substring(with: paragraphRange) as NSString
            let localRange = NSRange(location: 0, length: paragraphText.length)
            let match = bulletRegex?.firstMatch(in: paragraphText as String, options: [], range: localRange)
                ?? orderedRegex?.firstMatch(in: paragraphText as String, options: [], range: localRange)
            if let match, match.range.length > 0 {
                rangesToDelete.append(NSRange(location: paragraphRange.location + match.range.location, length: match.range.length))
            }
        }

        for range in rangesToDelete.reversed() {
            mutable.deleteCharacters(in: range)
        }
        return mutable
    }

    private static func removingSyntheticFinalNewline(
        from attributed: NSAttributedString,
        sourceHTML: String
    ) -> NSAttributedString {
        guard attributed.string.hasSuffix("\n"),
              !hasExplicitTerminalLineBreak(in: sourceHTML) else {
            return attributed
        }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.deleteCharacters(in: NSRange(location: mutable.length - 1, length: 1))
        return mutable
    }

    private static func hasExplicitTerminalLineBreak(in html: String) -> Bool {
        // Strip closing block/document tags from the end. A final <br> then
        // unambiguously represents a source newline, including inside the
        // <pre><code>...</code></pre> form used for code blocks.
        var value = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        let closingTag = try? NSRegularExpression(
            pattern: "</(?:html|body|p|div|li|ul|ol|pre|code|blockquote|td|th|h[1-6])\\s*>\\s*$",
            options: [.caseInsensitive]
        )
        while let closingTag,
              let match = closingTag.firstMatch(
                in: value,
                options: [],
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ) {
            guard let range = Range(match.range, in: value) else { break }
            value.removeSubrange(range)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let terminalBreak = try? NSRegularExpression(
            pattern: "<br\\b[^>]*>\\s*$",
            options: [.caseInsensitive]
        )
        return terminalBreak?.firstMatch(
            in: value,
            options: [],
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        ) != nil
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
        guard attributed.length > 0 else { return attributed }
        let fullRange = NSRange(location: 0, length: attributed.length)
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fontManager = NSFontManager.shared

        mutable.beginEditing()
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let replacement: NSFont
            if let font = value as? NSFont {
                let symbolicTraits = font.fontDescriptor.symbolicTraits
                let managerTraits = fontManager.traits(of: font)
                let isBold = symbolicTraits.contains(.bold) || managerTraits.contains(.boldFontMask)
                let isItalic = symbolicTraits.contains(.italic) || managerTraits.contains(.italicFontMask)
                let isMono = symbolicTraits.contains(.monoSpace)
                var candidate = isMono
                    ? NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: isBold ? .bold : .regular)
                    : NSFont.systemFont(ofSize: baseFont.pointSize, weight: isBold ? .bold : .regular)
                if isItalic {
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

    private static func normalizedColors(in attributed: NSAttributedString, baseColor: NSColor) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let fullRange = NSRange(location: 0, length: attributed.length)
        let mutable = NSMutableAttributedString(attributedString: attributed)

        mutable.beginEditing()
        var foregroundRanges: [(range: NSRange, hasLink: Bool)] = []
        mutable.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { _, range, _ in
            let hasLink = mutable.attribute(.link, at: range.location, effectiveRange: nil) != nil
            foregroundRanges.append((range: range, hasLink: hasLink))
        }
        for foreground in foregroundRanges {
            mutable.addAttribute(
                .foregroundColor,
                value: foreground.hasLink ? NSColor.linkColor : baseColor,
                range: foreground.range
            )
        }
        mutable.removeAttribute(.backgroundColor, range: fullRange)
        mutable.endEditing()
        return mutable
    }

    private static func applyingBaseAttributesIfMissing(to attributed: NSAttributedString, baseFont: NSFont, baseColor: NSColor) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let fullRange = NSRange(location: 0, length: attributed.length)
        let mutable = NSMutableAttributedString(attributedString: attributed)

        mutable.beginEditing()
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: baseFont, range: range)
            }
        }
        var missingForegroundRanges: [(range: NSRange, hasLink: Bool)] = []
        mutable.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                let hasLink = mutable.attribute(.link, at: range.location, effectiveRange: nil) != nil
                missingForegroundRanges.append((range: range, hasLink: hasLink))
            }
        }
        for foreground in missingForegroundRanges {
            mutable.addAttribute(
                .foregroundColor,
                value: foreground.hasLink ? NSColor.linkColor : baseColor,
                range: foreground.range
            )
        }
        mutable.endEditing()
        return mutable
    }
}

enum RichTextPasteboard {
    static func read(from pasteboard: NSPasteboard) -> RichTextPayload? {
        let rtf = pasteboard.data(forType: .rtf)
        let rawHTML = pasteboard.string(forType: .html)
            ?? pasteboard.data(forType: .html).flatMap { String(data: $0, encoding: .utf8) }
        if let rawHTML,
           let prepared = RichTextConverter.prepare(html: rawHTML) {
            return RichTextPayload(
                plain: prepared.plain,
                html: prepared.payload.html,
                rtf: rtf ?? prepared.payload.rtf
            )
        }

        if let plainString = pasteboard.string(forType: .string) {
            return RichTextPayload(
                plain: RichTextConverter.normalizedMarkdown(plainString.normalizedPlainText()),
                html: nil,
                rtf: rtf
            )
        }

        if let rtf {
            let prepared = RichTextConverter.prepare(payload: RichTextPayload(plain: "", html: nil, rtf: rtf))
            return prepared.payload
        }

        return nil
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

        // Keep the canonical plain fallback with visible bullets/numbers.  The
        // HTML and RTF representations carry true list semantics; this string
        // is for applications that understand neither representation.
        pasteboard.setString(payload.plain, forType: .string)
    }
}
