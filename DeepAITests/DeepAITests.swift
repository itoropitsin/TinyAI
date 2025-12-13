//
//  DeepAITests.swift
//  DeepAITests
//
//  Created by Ivan on 12/12/2025.
//

import Testing
@testable import DeepAI

struct DeepAITests {

    enum TestError: Error {
        case missingAPIKey
    }

    private func apiKey() throws -> String {
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        throw TestError.missingAPIKey
    }

    private func translate(service: TranslationService, text: String, targetLanguage: String, model: OpenAIModel) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            service.translate(text: text, targetLanguage: targetLanguage, modelOverride: model) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func containsCyrillic(_ text: String) -> Bool {
        return text.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil
    }

    @Test func translation_hello_to_russian_works_for_all_models() async throws {
        let key = try apiKey()
        let service = TranslationService()
        service.saveAPIKey(key)

        for model in OpenAIModel.allCases {
            let out = try await translate(service: service, text: "Hello", targetLanguage: "Russian", model: model)

            #expect(!out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Expect actual translation, not echo.
            #expect(out.lowercased() != "hello")

            // For Russian we expect Cyrillic characters in most natural translations.
            #expect(containsCyrillic(out))
        }
    }
}
