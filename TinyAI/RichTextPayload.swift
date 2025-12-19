import AppKit
import Foundation

struct RichTextPayload: Equatable {
    var plain: String
    var html: String?
    var rtf: Data?
}

enum RichTextHTMLSanitizer {
    static func sanitize(_ html: String) -> String {
        var result = html
        result = stripFontMarkupAndStyles(from: result)
        result = removeDuplicateListBullets(from: result)
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

        // Remove a literal bullet that appears inside <li> content (often duplicated by list styling).
        // Covers cases like:
        // - <li>• text</li>
        // - <li><p>• text</p></li>
        // - <li><span>•</span> text</li>
        // - <li><span><b>•</b></span> text</li>
        result = replacingRegex(
            in: result,
            pattern: "(<li\\b[^>]*>(?:\\s|&nbsp;|<[^>]+>)*)(?:&bull;|&#8226;|•|·|\\-|\\*)(?:\\s|&nbsp;)+",
            with: "$1",
            options: [.caseInsensitive]
        )

        // Clean up empty wrappers that may remain after removing the bullet glyph.
        result = replacingRegex(in: result, pattern: "<span\\b[^>]*>\\s*</span>", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "<b\\b[^>]*>\\s*</b>", with: "", options: [.caseInsensitive])
        result = replacingRegex(in: result, pattern: "<strong\\b[^>]*>\\s*</strong>", with: "", options: [.caseInsensitive])

        return result
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

enum RichTextConverter {
    static func attributedString(from payload: RichTextPayload) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let baseColor = NSColor.labelColor

        if let rtf = payload.rtf,
           let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            let normalized = normalizedListMarkers(in: normalizedFonts(in: attributed, baseFont: baseFont))
            return applyingBaseAttributesIfMissing(to: normalized, baseFont: baseFont, baseColor: baseColor)
        }

        if let html = payload.html,
           let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
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
            let normalized = normalizedListMarkers(in: normalizedFonts(in: attributed, baseFont: baseFont))
            return applyingBaseAttributesIfMissing(to: normalized, baseFont: baseFont, baseColor: baseColor)
        }

        return NSAttributedString(string: payload.plain.normalizedPlainText(), attributes: [
            .font: baseFont,
            .foregroundColor: baseColor
        ])
    }

    static func payload(fromMarkdown markdown: String) -> RichTextPayload {
        let normalizedMarkdown = normalizedMarkdown(markdown)
        let trimmedNewlines = normalizedMarkdown.trimmingCharacters(in: .newlines)
        guard !trimmedNewlines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RichTextPayload(plain: "", html: nil, rtf: nil)
        }

        guard #available(macOS 12.0, *) else {
            let plain = trimmedNewlines.normalizedPlainText()
            return RichTextPayload(plain: plain, html: nil, rtf: nil)
        }

        let baseFont = NSFont.preferredFont(forTextStyle: .body)
        let baseColor = NSColor.labelColor

        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            options.failurePolicy = .returnPartiallyParsedIfPossible
            let prepared = preparedMarkdown(trimmedNewlines)
            let attributed = try AttributedString(markdown: prepared, options: options)
            let attributedString = NSAttributedString(attributed)
            let normalized = normalizedListMarkers(in: normalizedFonts(in: attributedString, baseFont: baseFont))
            let finalized = applyingBaseAttributesIfMissing(to: normalized, baseFont: baseFont, baseColor: baseColor)
            let rtf = self.rtf(from: finalized)
            let html = self.html(from: finalized)
            let plain = finalized.string.normalizedPlainText()
            return RichTextPayload(plain: plain, html: html, rtf: rtf)
        } catch {
            let plain = trimmedNewlines.normalizedPlainText()
            return RichTextPayload(plain: plain, html: nil, rtf: nil)
        }
    }

    static func normalizedMarkdown(_ raw: String) -> String {
        let normalizedNewlines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        lines.reserveCapacity(normalizedNewlines.count / 20)

        normalizedNewlines.enumerateLines { line, _ in
            // Convert common bullet glyphs into Markdown list markers.
            if let converted = convertBulletLineToMarkdown(line) {
                lines.append(converted)
            } else {
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func convertBulletLineToMarkdown(_ line: String) -> String? {
        // Preserve indentation and replace "• " / "· " / "◦ " etc with "- ".
        let bulletChars: Set<Character> = ["•", "·", "◦", "▪", "‣"]

        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return nil }
        let bullet = line[index]
        guard bulletChars.contains(bullet) else { return nil }

        let afterBullet = line.index(after: index)
        guard afterBullet < line.endIndex else { return nil }
        guard line[afterBullet] == " " || line[afterBullet] == "\t" else { return nil }

        let indent = String(line[..<index])
        let rest = String(line[line.index(after: afterBullet)...])
        return indent + "- " + rest
    }

    @available(macOS 12.0, *)
    private static func preparedMarkdown(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func normalizedListMarkers(in attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }

        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullNSString = mutable.string as NSString

        let bulletPattern = "^(?:[\\s\\u00A0]*)(?:[•·◦▪‣\\-*])(?:[\\s\\u00A0]+)"
        let orderedPattern = "^(?:[\\s\\u00A0]*)(?:(?:\\(?\\d{1,3}[\\).])|(?:\\d{1,3})|(?:[A-Za-z][\\).]))(?:[\\s\\u00A0]+)"
        let bulletRegex = try? NSRegularExpression(pattern: bulletPattern, options: [])
        let orderedRegex = try? NSRegularExpression(pattern: orderedPattern, options: [])

        var location = 0
        while location < mutable.length {
            let paragraphRange = fullNSString.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraphRange)

            guard paragraphRange.length > 0 else { continue }
            guard let paragraphStyle = mutable.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle else {
                continue
            }
            guard !paragraphStyle.textLists.isEmpty else { continue }

            // Remove duplicated literal markers that were copied into the content (e.g. "1. " inside an <ol><li>).
            let paragraphText = fullNSString.substring(with: paragraphRange) as NSString
            let localRange = NSRange(location: 0, length: paragraphText.length)

            let match = bulletRegex?.firstMatch(in: paragraphText as String, options: [], range: localRange)
                ?? orderedRegex?.firstMatch(in: paragraphText as String, options: [], range: localRange)

            guard let match, match.range.length > 0 else { continue }

            let deleteRange = NSRange(location: paragraphRange.location + match.range.location, length: match.range.length)
            mutable.deleteCharacters(in: deleteRange)
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
        guard let data = html.data(using: .utf8),
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

        return attributed.string.normalizedPlainText()
    }
}

enum RichTextPasteboard {
    static func read(from pasteboard: NSPasteboard) -> RichTextPayload? {
        let rtf = pasteboard.data(forType: .rtf)
        let html = pasteboard.string(forType: .html)
            ?? pasteboard.data(forType: .html).flatMap { String(data: $0, encoding: .utf8) }

        let plain: String
        if let plainString = pasteboard.string(forType: .string) {
            plain = plainString.normalizedPlainText()
        } else if let html {
            plain = RichTextConverter.plain(fromHTML: html)
        } else if let rtf,
                  let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            plain = attributed.string.normalizedPlainText()
        } else {
            return nil
        }

        return RichTextPayload(plain: plain, html: html, rtf: rtf)
    }

    static func write(_ payload: RichTextPayload, to pasteboard: NSPasteboard) {
        let attributed = RichTextConverter.attributedString(from: payload)
        let rtf = payload.rtf ?? RichTextConverter.rtf(from: attributed)
        let html = payload.html ?? RichTextConverter.html(from: attributed)

        pasteboard.clearContents()

        if let rtf {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let html, let data = html.data(using: .utf8) {
            pasteboard.setData(data, forType: .html)
        }

        pasteboard.setString(payload.plain, forType: .string)
    }
}
