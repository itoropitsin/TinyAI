//
//  TinyAITests.swift
//  TinyAITests
//
//  Created by Ivan on 12/12/2025.
//

import Testing
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
        #expect(!TranslationService.isSupportedOpenAITextModel("gpt-4o-realtime-preview"))
        #expect(!TranslationService.isSupportedOpenAITextModel("text-embedding-3-small"))
        #expect(!TranslationService.isSupportedOpenAITextModel("dall-e-3"))
    }

    @Test func popupHotkeyValidation_allowsDefaultDoubleCopy_butProtectsEditingShortcuts() {
        let copy = KeyboardShortcut(keyCode: 8, modifiers: [.command])
        #expect(KeyboardMonitor.validationError(for: copy, pressMode: .doublePress) == nil)
        #expect(KeyboardMonitor.validationError(for: copy, pressMode: .singlePress) != nil)

        let paste = KeyboardShortcut(keyCode: 9, modifiers: [.command])
        #expect(KeyboardMonitor.validationError(for: paste, pressMode: .doublePress) != nil)
    }
}
