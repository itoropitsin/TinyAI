//
//  TinyAITests.swift
//  TinyAITests
//
//  Created by Ivan on 12/12/2025.
//

import Testing
import Foundation
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

    @Test func preferredPopupPayload_usesFreshClipboardBeforeAccessibility() {
        let pending = RichTextPayload(plain: "pending", html: nil, rtf: nil)
        let fresh = RichTextPayload(plain: "fresh", html: "<p>fresh</p>", rtf: nil)
        let accessibility = RichTextPayload(plain: "accessibility", html: nil, rtf: nil)

        #expect(KeyboardMonitor.preferredPopupPayload(
            pendingClipboard: pending,
            freshClipboard: fresh,
            accessibility: accessibility
        )?.plain == "pending")
        #expect(KeyboardMonitor.preferredPopupPayload(
            pendingClipboard: nil,
            freshClipboard: fresh,
            accessibility: accessibility
        )?.plain == "fresh")
        #expect(KeyboardMonitor.preferredPopupPayload(
            pendingClipboard: RichTextPayload(plain: " ", html: nil, rtf: nil),
            freshClipboard: nil,
            accessibility: accessibility
        )?.plain == "accessibility")
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
