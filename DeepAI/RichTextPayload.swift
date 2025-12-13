import AppKit

struct RichTextPayload: Equatable {
    var plain: String
    var html: String?
    var rtf: Data?
}

enum RichTextConverter {
    static func attributedString(from payload: RichTextPayload) -> NSAttributedString {
        if let rtf = payload.rtf,
           let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return attributed
        }

        if let html = payload.html,
           let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
           ) {
            return attributed
        }

        return NSAttributedString(string: payload.plain)
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

        return attributed.string
    }
}

enum RichTextPasteboard {
    static func read(from pasteboard: NSPasteboard) -> RichTextPayload? {
        let rtf = pasteboard.data(forType: .rtf)
        let html = pasteboard.string(forType: .html)
            ?? pasteboard.data(forType: .html).flatMap { String(data: $0, encoding: .utf8) }

        let plain: String
        if let plainString = pasteboard.string(forType: .string) {
            plain = plainString
        } else if let html {
            plain = RichTextConverter.plain(fromHTML: html)
        } else if let rtf,
                  let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            plain = attributed.string
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
