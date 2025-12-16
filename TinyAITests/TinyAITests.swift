//
//  TinyAITests.swift
//  TinyAITests
//
//  Created by Ivan on 12/12/2025.
//

import Testing
@testable import TinyAI

struct TinyAITests {

    enum TestError: Error {
        case missingAPIKey
    }

    private func apiKey() throws -> String {
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        throw TestError.missingAPIKey
    }

    private func translate(service: TranslationService, text: String, targetLanguage: String, model: LLMModel) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            service.translate(text: text, targetLanguage: targetLanguage, modelOverride: model) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func containsCyrillic(_ text: String) -> Bool {
        return text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
    }

    @Test @MainActor func ax_fullscreen_detection_does_not_crash() {
        let delegate = AppDelegate()
        let value = delegate.isFrontmostWindowFullscreen()
        #expect(value == true || value == false)
    }

    @Test func translation_hello_to_russian_works_for_all_models() async throws {
        let key = try apiKey()
        let service = TranslationService()
        service.saveAPIKey(key)

        for model in OpenAIModel.allCases {
            let llmModel = LLMModel(provider: .openAI, name: model.rawValue)
            let out = try await translate(service: service, text: "Hello", targetLanguage: "Russian", model: llmModel)

            #expect(!out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Expect actual translation, not echo.
            #expect(out.lowercased() != "hello")

            // For Russian we expect Cyrillic characters in most natural translations.
            #expect(containsCyrillic(out))
        }
    }
}
