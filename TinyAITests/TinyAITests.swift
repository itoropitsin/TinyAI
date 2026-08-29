//
//  TinyAITests.swift
//  TinyAITests
//
//  Created by Ivan on 12/12/2025.
//

import Testing
import Foundation
import AppKit
@testable import TinyAI

struct TinyAITests {

    @Test @MainActor func ax_fullscreen_detection_does_not_crash() {
        let delegate = AppDelegate()
        let value = delegate.isFrontmostWindowFullscreen()
        #expect(value == true || value == false)
    }

    @Test func normalizedMarkdown_preservesIndentation_whenConvertingBullets() {
        let input = "  • First\n\t• Second\n    • Third"
        let output = RichTextConverter.normalizedMarkdown(input)
        #expect(output.contains("  - First"))
        #expect(output.contains("\t- Second"))
        #expect(output.contains("    - Third"))
    }

    @Test func normalizedMarkdown_convertsSlackPrivateUseBullets_butProtectsTextAndCode() {
        let marker = RichTextListMarkers.slackPrivateUseBullet
        let input = "\(marker) First\n  \(marker) Second\nkeep\(marker)inside\n```\n\(marker) code\n```"
        let output = RichTextConverter.normalizedMarkdown(input)

        #expect(output == "- First\n  - Second\nkeep\(marker)inside\n```\n\(marker) code\n```")
        #expect(RichTextConverter.normalizedMarkdown("\(marker)without-space") == "\(marker)without-space")
        #expect(RichTextConverter.normalizedMarkdown("\(marker)\nnext") == "\(marker)\nnext")
    }

    @Test func proseStartingWithLetters_isNotParsedAsAnOrderedList() {
        let source = "As we discussed on the call with security - let's update the columns naming in RBAC:\n- System Admins\n- Role Admin"
        let prepared = RichTextConverter.prepare(markdown: source)

        #expect(prepared.plain == "As we discussed on the call with security - let's update the columns naming in RBAC:\n• System Admins\n• Role Admin")
        #expect(RichTextConverter.structureSignature(of: prepared.attributed).blocks == [
            "paragraph",
            "list:unordered:1:item",
            "list:unordered:1:item"
        ])

        let firstParagraphRange = (prepared.attributed.string as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        let firstParagraphStyle = prepared.attributed.attribute(
            .paragraphStyle,
            at: firstParagraphRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(firstParagraphStyle?.textLists.isEmpty != false)
    }

    @Test func htmlSanitizer_removesSlackMarkers_onlyInListPositions() {
        let marker = RichTextListMarkers.slackPrivateUseBullet
        let html = "<ul><li>\(marker) <strong>First</strong></li><li><span><b>\(marker)</b></span> Second</li></ul>"
            + "<p><span>\(marker)</span> Standalone</p><p>keep\(marker)inside</p>"
            + "<ul><li>&#58630; Third</li><li>&#xE506; Fourth</li></ul><pre>\(marker) code</pre>"

        let sanitized = RichTextHTMLSanitizer.sanitize(html)

        #expect(!sanitized.contains("&#58630;"))
        #expect(!sanitized.contains("&#xE506;"))
        #expect(sanitized.contains("<strong>First</strong>"))
        #expect(sanitized.contains("•"))
        #expect(!sanitized.contains("<span></span>"))
        #expect(!sanitized.contains("<b></b>"))
        #expect(sanitized.contains("<pre>\(marker) code</pre>"))
        #expect(sanitized.contains("<p>keep\(marker)inside</p>"))
        let withoutCode = sanitized.replacingOccurrences(of: "<pre>\(marker) code</pre>", with: "")
        let withoutOrdinaryText = withoutCode.replacingOccurrences(of: "<p>keep\(marker)inside</p>", with: "")
        #expect(!withoutOrdinaryText.contains(marker))
    }

    @Test func htmlSanitizer_stripsSourceTypographyAndColors() {
        let html = #"<p style="font-family: SlackFont; font-size: 48px; color: #ff00aa; background-color: yellow; border-color: black"><strong>Text</strong></p>"#
        let sanitized = RichTextHTMLSanitizer.sanitize(html)

        #expect(!sanitized.contains("font-family"))
        #expect(!sanitized.contains("font-size"))
        #expect(!sanitized.contains("color: #ff00aa"))
        #expect(!sanitized.contains("background-color"))
        #expect(sanitized.contains("border-color: black"))
        #expect(sanitized.contains("<strong>Text</strong>"))
    }

    @Test func plainHTML_preservesPrivateUseCharacters_insideCodeBlocks() {
        let marker = RichTextListMarkers.slackPrivateUseBullet
        let plain = RichTextConverter.plain(fromHTML: "<p>\(marker) item</p><pre>\(marker) code</pre>")

        #expect(plain.contains("- item"))
        #expect(plain.contains("\(marker) code"))
    }

    @Test func markdownPayload_usesVisibleBullets_andKeepsInlineFormatting() {
        let payload = RichTextConverter.payload(fromMarkdown: "Intro\n\n- **One**\n  - [Two](https://example.com)\n1. Three")

        #expect(payload.plain == "Intro\n\n• One\n  • Two\n1. Three")
        #expect(payload.html?.contains("One") == true)
        #expect(payload.html?.contains("https://example.com") == true)
    }

    @Test func attributedPayload_replacesPrivateUseBulletBeforeFontNormalization() {
        let marker = RichTextListMarkers.slackPrivateUseBullet
        let source = NSAttributedString(string: "\(marker) First\n")
        let rtf = RichTextConverter.rtf(from: source)
        let payload = RichTextPayload(plain: "\(marker) First", html: nil, rtf: rtf)
        let converted = RichTextConverter.attributedString(from: payload).string

        #expect(converted.contains("• First"))
        #expect(!converted.contains(marker))
    }

    @Test func preferredPopupPayload_prefersRichRepresentation_beforePlainFallback() {
        let pending = RichTextPayload(plain: "pending", html: nil, rtf: nil)
        let fresh = RichTextPayload(plain: "fresh", html: "<p>fresh</p>", rtf: nil)
        let accessibility = RichTextPayload(plain: "accessibility", html: nil, rtf: nil)

        #expect(KeyboardMonitor.preferredPopupPayload(
            pendingClipboard: pending,
            freshClipboard: fresh,
            accessibility: accessibility
        )?.plain == "fresh")
        #expect(KeyboardMonitor.preferredPopupPayload(
            pendingClipboard: nil,
            freshClipboard: fresh,
            accessibility: accessibility
        )?.plain == "fresh")
        #expect(KeyboardMonitor.preferredPopupPayload(
            pendingClipboard: pending,
            freshClipboard: nil,
            accessibility: RichTextPayload(plain: "rich accessibility", html: nil, rtf: Data([1]))
        )?.plain == "rich accessibility")
        #expect(KeyboardMonitor.preferredPopupPayload(
            pendingClipboard: RichTextPayload(plain: " ", html: nil, rtf: nil),
            freshClipboard: nil,
            accessibility: accessibility
        )?.plain == "accessibility")
    }

    @Test func translationLanguageMode_autoPromptDelegatesDirectionToModel() {
        let mode = TranslationLanguageMode.automatic(main: "Russian", additional: "English")
        let instruction = TranslationService.translationDirectionInstruction(for: mode)

        #expect(instruction.contains("Main language: Russian"))
        #expect(instruction.contains("Additional language: English"))
        #expect(instruction.contains("predominantly Russian"))
        #expect(instruction.contains("translate to English"))
        #expect(instruction.contains("predominantly English"))
        #expect(instruction.contains("translate to Russian"))
        #expect(instruction.contains("human-readable prose"))
        #expect(instruction.contains("URLs, domains, paths, code"))
        #expect(instruction.contains("return it unchanged"))
    }

    @Test func translationLanguageMode_fixedPromptKeepsExplicitTarget() {
        let instruction = TranslationService.translationDirectionInstruction(for: .fixed("German"))
        #expect(instruction == "Translate from the detected source language to German naturally and clearly.")
    }

    @Test func sharedRichPayload_preservesFormattingForDisplayAndPaste() {
        let payload = RichTextConverter.payload(fromMarkdown: "Intro\n\n- **One**\n  - [Two](https://example.com)\n1. Three")
        let displayed = RichTextConverter.attributedString(from: payload)
        let oneLocation = (displayed.string as NSString).range(of: "One").location
        let twoLocation = (displayed.string as NSString).range(of: "Two").location
        let oneStyle = displayed.attribute(.paragraphStyle, at: oneLocation, effectiveRange: nil) as? NSParagraphStyle
        let twoStyle = displayed.attribute(.paragraphStyle, at: twoLocation, effectiveRange: nil) as? NSParagraphStyle

        #expect(displayed.string.contains("One"))
        #expect(displayed.string.contains("Two"))
        #expect(oneStyle?.textLists.count == 1)
        #expect(twoStyle?.textLists.count == 2)
        #expect(payload.html?.contains("https://example.com") == true)
        #expect(payload.html?.contains("strong") == true)
        #expect(payload.rtf != nil)
    }

    @Test func preparedMarkdown_materializesOnlyRequestedFontTraits() {
        let prepared = RichTextConverter.prepare(markdown: "Normal **bold** *italic* `code`")
        let text = prepared.attributed

        func font(at substring: String) -> NSFont? {
            let range = (text.string as NSString).range(of: substring)
            guard range.location != NSNotFound else { return nil }
            return text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        }

        let normal = font(at: "Normal")
        let bold = font(at: "bold")
        let italic = font(at: "italic")
        let code = font(at: "code")
        #expect(normal?.fontDescriptor.symbolicTraits.contains(.bold) == false)
        #expect(normal?.fontDescriptor.symbolicTraits.contains(.italic) == false)
        #expect(normal?.fontDescriptor.symbolicTraits.contains(.monoSpace) == false)
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(italic?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(code?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        #expect(Set([normal?.pointSize, bold?.pointSize, italic?.pointSize, code?.pointSize].compactMap { $0 }).count == 1)
    }

    @Test func preparedPayload_roundTripDoesNotChangeSemanticFormatting() {
        let prepared = RichTextConverter.prepare(markdown: "Normal **bold** *italic* `code`\n\n- one\n  - two\n1. three")
        let roundTrip = RichTextConverter.prepare(payload: prepared.payload)
        let rtfOnly = RichTextConverter.prepare(payload: RichTextPayload(
            plain: prepared.plain,
            html: nil,
            rtf: prepared.payload.rtf
        ))

        #expect(roundTrip.plain == prepared.plain)
        #expect(RichTextConverter.structureSignature(of: roundTrip.attributed) == RichTextConverter.structureSignature(of: prepared.attributed))
        #expect(RichTextConverter.structureSignature(of: rtfOnly.attributed) == RichTextConverter.structureSignature(of: prepared.attributed))
        #expect(roundTrip.payload.html?.contains("<strong>bold</strong>") == true)
        #expect(roundTrip.payload.html?.contains("<em>italic</em>") == true)
        #expect(roundTrip.payload.html?.contains("<code>code</code>") == true)
        #expect(roundTrip.payload.html?.contains("<ul>") == true)
        #expect(roundTrip.payload.html?.contains("<ol>") == true)
        #expect(roundTrip.payload.html?.contains("font-family") == false)
        #expect(roundTrip.payload.html?.contains("font-size") == false)
        #expect(roundTrip.payload.html?.contains("color:") == false)
    }

    @Test func preparedPayload_roundTripPreservesTerminalLineBreaks() {
        for source in [
            "Paragraph\n",
            "Paragraph\n\n",
            "- item\n",
            "```\ncode\n```\n"
        ] {
            let prepared = RichTextConverter.prepare(markdown: source)
            let roundTrip = RichTextConverter.prepare(payload: prepared.payload)
            #expect(roundTrip.plain == prepared.plain)
        }
    }

    @Test func preparedMarkdown_createsTrueNestedListsAndVisiblePlainFallback() {
        let prepared = RichTextConverter.prepare(markdown: "- top\n  - nested\n1. numbered")
        let firstListStyle = prepared.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let nestedLocation = (prepared.attributed.string as NSString).range(of: "nested").location
        let nestedListStyle = prepared.attributed.attribute(.paragraphStyle, at: nestedLocation, effectiveRange: nil) as? NSParagraphStyle

        #expect(firstListStyle?.textLists.count == 1)
        #expect(nestedListStyle?.textLists.count == 2)
        #expect(prepared.plain == "• top\n  • nested\n1. numbered")
    }

    @Test func pasteboardPlainFallback_keepsVisibleListMarkers() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TinyAI.Tests.\(UUID().uuidString)"))
        let payload = RichTextConverter.prepare(markdown: "- one\n1. two").payload
        RichTextPasteboard.write(payload, to: pasteboard)

        #expect(pasteboard.string(forType: NSPasteboard.PasteboardType.string) == "• one\n1. two")
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType.html) != nil)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType.rtf) != nil)
    }

    @Test func openAIModelFiltering_keepsTextModels_andDropsNonTextModels() {
        #expect(TranslationService.isSupportedOpenAITextModel("gpt-4o"))
        #expect(TranslationService.isSupportedOpenAITextModel("o3-mini"))
        #expect(TranslationService.isSupportedOpenAITextModel("chatgpt-4o-latest"))
        #expect(TranslationService.isSupportedOpenAITextModel("ft:gpt-4o-mini:org:custom:abc123"))
        #expect(!TranslationService.isSupportedOpenAITextModel("gpt-4o-realtime-preview"))
        #expect(!TranslationService.isSupportedOpenAITextModel("text-embedding-3-small"))
        #expect(!TranslationService.isSupportedOpenAITextModel("dall-e-3"))
    }

    @Test func openAIModelParsing_returnsSupportedModels_andFiltersUnsupportedModels() throws {
        let payload = """
        {
          "object": "list",
          "data": [
            {"id": "gpt-5.2"},
            {"id": "o4-mini"},
            {"id": "ft:gpt-4o-mini:org:custom:abc123"},
            {"id": "gpt-4o-realtime-preview"},
            {"id": "gpt-image-1"},
            {"id": "text-embedding-3-small"},
            {"id": "dall-e-3"}
          ]
        }
        """.data(using: .utf8)!

        let entries = try TranslationService.parseOpenAIModelEntries(payload)
        let names = Set(entries.map(\.model.name))

        #expect(names == Set([
            "gpt-5.2",
            "o4-mini",
            "ft:gpt-4o-mini:org:custom:abc123"
        ]))
    }

    @Test func modelCatalogMerge_addsVisibleUniqueModels_andPreservesExistingSettings() {
        let existing = LLMModel(provider: .openAI, name: "gpt-5-mini")
        let unavailable = LLMModel(provider: .openAI, name: "gpt-4o")
        let newModel = LLMModel(provider: .openAI, name: "o4-mini")
        let deleted = LLMModel(provider: .openAI, name: "gpt-4.1")

        let result = TranslationService.mergeFetchedModels(
            existing: [
                LLMModelEntry(model: existing, displayName: existing.name),
                LLMModelEntry(model: unavailable, displayName: unavailable.name)
            ],
            fetched: [
                LLMModelEntry(model: existing, displayName: existing.name),
                LLMModelEntry(model: newModel, displayName: newModel.name),
                LLMModelEntry(model: newModel, displayName: newModel.name),
                LLMModelEntry(model: deleted, displayName: deleted.name)
            ],
            visibility: [existing.key: false],
            availability: [existing.key: true, unavailable.key: true],
            provider: .openAI,
            deletedKeys: [deleted.key]
        )

        #expect(result.models.map(\.model.key) == [existing.key, unavailable.key, newModel.key])
        #expect(result.visibility[existing.key] == false)
        #expect(result.visibility[newModel.key] == true)
        #expect(result.availability[existing.key] == true)
        #expect(result.availability[unavailable.key] == false)
        #expect(result.availability[newModel.key] == true)
        #expect(!result.models.contains { $0.model == deleted })
    }

    @Test func openAIModelParsing_returnsEmptyForOnlyUnsupportedModels() throws {
        let payload = """
        {"data": [{"id": "gpt-4o-realtime-preview"}, {"id": "text-embedding-3-small"}]}
        """.data(using: .utf8)!

        let entries = try TranslationService.parseOpenAIModelEntries(payload)
        #expect(entries.isEmpty)
    }

    @Test func popupHotkeyValidation_allowsDefaultDoubleCopy_butProtectsEditingShortcuts() {
        let copy = KeyboardShortcut(keyCode: 8, modifiers: [.command])
        #expect(KeyboardMonitor.validationError(for: copy, pressMode: .doublePress) == nil)
        #expect(KeyboardMonitor.validationError(for: copy, pressMode: .singlePress) != nil)

        let paste = KeyboardShortcut(keyCode: 9, modifiers: [.command])
        #expect(KeyboardMonitor.validationError(for: paste, pressMode: .doublePress) != nil)
    }

    @Test func mainProcessingDelay_isShortForPastes_andLongerForTyping() {
        #expect(MainTranslationView.processingDelay(for: "", newValue: "Pasted text") == 0.05)
        #expect(MainTranslationView.processingDelay(for: "one", newValue: "one\ntwo") == 0.05)
        #expect(MainTranslationView.processingDelay(for: "a", newValue: "ab") == 0.30)
    }
}
