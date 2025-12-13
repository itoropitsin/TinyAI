import Foundation
import Combine

enum OpenAIModel: String, CaseIterable, Identifiable {
    case gpt52 = "gpt-5.2"
    case gpt5Mini = "gpt-5-mini"
    case gpt5Nano = "gpt-5-nano"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt52:
            return "gpt-5.2"
        case .gpt5Mini:
            return "gpt-5-mini"
        case .gpt5Nano:
            return "gpt-5-nano"
        }
    }
}

class TranslationService: ObservableObject {
    @Published var apiKey: String = "" {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: apiKeyDefaultsKey)
        }
    }

    @Published var isTranslationEnabled: Bool = true {
        didSet {
            if !isTranslationEnabled && !isGrammarEnabled {
                isTranslationEnabled = true
                return
            }
            UserDefaults.standard.set(isTranslationEnabled, forKey: translationEnabledDefaultsKey)
        }
    }

    @Published var isGrammarEnabled: Bool = true {
        didSet {
            if !isGrammarEnabled && !isTranslationEnabled {
                isGrammarEnabled = true
                return
            }
            UserDefaults.standard.set(isGrammarEnabled, forKey: grammarEnabledDefaultsKey)
        }
    }

    @Published var translationModel: OpenAIModel = .gpt5Mini {
        didSet {
            UserDefaults.standard.set(translationModel.rawValue, forKey: translationModelDefaultsKey)
        }
    }

    @Published var grammarModel: OpenAIModel = .gpt5Mini {
        didSet {
            UserDefaults.standard.set(grammarModel.rawValue, forKey: grammarModelDefaultsKey)
        }
    }

    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    private let apiKeyDefaultsKey = "OpenAIAPIKey"
    private let legacyModelDefaultsKey = "OpenAIModel"
    private let translationModelDefaultsKey = "OpenAITranslationModel"
    private let grammarModelDefaultsKey = "OpenAIGrammarModel"
    private let translationEnabledDefaultsKey = "OpenAITranslationEnabled"
    private let grammarEnabledDefaultsKey = "OpenAIGrammarEnabled"
    
    init() {
        if let savedKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) {
            apiKey = savedKey
        }

        if UserDefaults.standard.object(forKey: translationEnabledDefaultsKey) != nil {
            isTranslationEnabled = UserDefaults.standard.bool(forKey: translationEnabledDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: grammarEnabledDefaultsKey) != nil {
            isGrammarEnabled = UserDefaults.standard.bool(forKey: grammarEnabledDefaultsKey)
        }

        var loadedTranslationModel: OpenAIModel?
        if let savedTranslationModelRaw = UserDefaults.standard.string(forKey: translationModelDefaultsKey),
           let savedModel = OpenAIModel(rawValue: savedTranslationModelRaw) {
            loadedTranslationModel = savedModel
        } else if let savedLegacyModelRaw = UserDefaults.standard.string(forKey: legacyModelDefaultsKey),
                  let savedModel = OpenAIModel(rawValue: savedLegacyModelRaw) {
            loadedTranslationModel = savedModel
        }
        if let loadedTranslationModel {
            translationModel = loadedTranslationModel
        }

        if let savedGrammarModelRaw = UserDefaults.standard.string(forKey: grammarModelDefaultsKey),
           let savedModel = OpenAIModel(rawValue: savedGrammarModelRaw) {
            grammarModel = savedModel
        } else {
            grammarModel = translationModel
        }

        if !isTranslationEnabled && !isGrammarEnabled {
            isTranslationEnabled = true
        }
    }
    
    func saveAPIKey(_ key: String) {
        apiKey = key
    }

    func saveTranslationModel(_ model: OpenAIModel) {
        translationModel = model
    }

    func saveGrammarModel(_ model: OpenAIModel) {
        grammarModel = model
    }

    func saveIsTranslationEnabled(_ enabled: Bool) {
        isTranslationEnabled = enabled
    }

    func saveIsGrammarEnabled(_ enabled: Bool) {
        isGrammarEnabled = enabled
    }

    private func buildRequestBody(text: String, targetLanguage: String, model: OpenAIModel) -> [String: Any] {
        let systemPrompt = """
You are a professional translator. Your priority is to preserve meaning and intent.
Translate from Auto-detect to \(targetLanguage) naturally and clearly.

Rules:
- Preserve meaning over literal wording.
- Keep tone (formal/informal), politeness, and emotional nuance.
- Preserve formatting: line breaks, lists, numbering, emojis, code blocks, and URLs.
- Do not add explanations, notes, or commentary.
- Do not censor or soften content.
- If a term is ambiguous, choose the most likely meaning from context. If truly unclear, keep the original term in parentheses after the translation.
- Keep names, product names, and IDs unchanged unless there is a widely accepted translation.
Output only the translation.
"""

        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": text
                ]
            ],
            "max_completion_tokens": 1000
        ]

        switch model {
        case .gpt52:
            requestBody["temperature"] = 0.3
        case .gpt5Mini, .gpt5Nano:
            break
        }

        return requestBody
    }

    private func buildGrammarFixRequestBody(text: String, model: OpenAIModel) -> [String: Any] {
        let systemPrompt = """
You are an expert editor.
Fix punctuation, grammar, and awkward or unclear constructions while preserving the original meaning and writing style.

Rules:
- Keep the original language.
- Preserve tone (formal/informal), voice, and intent.
- Preserve formatting: line breaks, lists, numbering, emojis, code blocks, and URLs.
- Do not add explanations, notes, or commentary.
- Output only the corrected version of the text.
"""

        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": text
                ]
            ],
            "max_completion_tokens": 1000
        ]

        switch model {
        case .gpt52:
            requestBody["temperature"] = 0.2
        case .gpt5Mini, .gpt5Nano:
            break
        }

        return requestBody
    }

    private func performChatCompletion(requestBody: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            completion(.failure(TranslationError.apiKeyMissing))
            return
        }

        guard let url = URL(string: baseURL) else {
            completion(.failure(TranslationError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(TranslationError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorData["error"] as? [String: Any],
                       let message = errorMessage["message"] as? String {
                        completion(.failure(TranslationError.apiError(message)))
                    } else {
                        completion(.failure(TranslationError.httpError(httpResponse.statusCode)))
                    }
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let choices = json?["choices"] as? [[String: Any]],
                          let firstChoice = choices.first,
                          let message = firstChoice["message"] as? [String: Any],
                          let content = message["content"] as? String else {
                        completion(.failure(TranslationError.invalidResponse))
                        return
                    }

                    let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.success(text))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func translate(text: String, targetLanguage: String, completion: @escaping (Result<String, Error>) -> Void) {
        translate(text: text, targetLanguage: targetLanguage, modelOverride: nil, completion: completion)
    }

    func translate(text: String, targetLanguage: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }
        
        isTranslating = true
        errorMessage = nil

        let modelToUse = modelOverride ?? translationModel
        translateText(text: text, targetLanguage: targetLanguage, modelOverride: modelToUse) { [weak self] result in
            self?.isTranslating = false
            switch result {
            case .success:
                completion(result)
            case .failure(let error):
                if let localizedError = error as? LocalizedError {
                    self?.errorMessage = localizedError.errorDescription
                } else {
                    self?.errorMessage = error.localizedDescription
                }
                completion(result)
            }
        }
    }

    func translateText(text: String, targetLanguage: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }

        let modelToUse = modelOverride ?? translationModel
        let requestBody = buildRequestBody(text: text, targetLanguage: targetLanguage, model: modelToUse)
        performChatCompletion(requestBody: requestBody, completion: completion)
    }

    func grammarFix(text: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }

        let modelToUse = modelOverride ?? grammarModel
        let requestBody = buildGrammarFixRequestBody(text: text, model: modelToUse)
        performChatCompletion(requestBody: requestBody, completion: completion)
    }
}

enum TranslationError: LocalizedError {
    case apiKeyMissing
    case emptyText
    case invalidURL
    case noData
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API ключ не установлен"
        case .emptyText:
            return "Текст для перевода пуст"
        case .invalidURL:
            return "Неверный URL"
        case .noData:
            return "Нет данных от сервера"
        case .invalidResponse:
            return "Неверный формат ответа"
        case .httpError(let code):
            return "HTTP ошибка: \(code)"
        case .apiError(let message):
            return message
        }
    }
}

