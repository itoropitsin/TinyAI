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
