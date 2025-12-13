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
    @Published var apiKey: String = ""
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    @Published var selectedModel: OpenAIModel = .gpt5Mini
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let modelDefaultsKey = "OpenAIModel"
    
    init() {
        // Загружаем API ключ из UserDefaults
        if let savedKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey") {
            apiKey = savedKey
        }

        if let savedModelRaw = UserDefaults.standard.string(forKey: modelDefaultsKey),
           let savedModel = OpenAIModel(rawValue: savedModelRaw) {
            selectedModel = savedModel
        }
    }
    
    func saveAPIKey(_ key: String) {
        apiKey = key
        UserDefaults.standard.set(key, forKey: "OpenAIAPIKey")
    }

    func saveSelectedModel(_ model: OpenAIModel) {
        selectedModel = model
        UserDefaults.standard.set(model.rawValue, forKey: modelDefaultsKey)
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
    
    func translate(text: String, targetLanguage: String, completion: @escaping (Result<String, Error>) -> Void) {
        translate(text: text, targetLanguage: targetLanguage, modelOverride: nil, completion: completion)
    }

    func translate(text: String, targetLanguage: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            completion(.failure(TranslationError.apiKeyMissing))
            return
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }
        
        isTranslating = true
        errorMessage = nil

        let modelToUse = modelOverride ?? selectedModel
        let requestBody = buildRequestBody(text: text, targetLanguage: targetLanguage, model: modelToUse)
        
        guard let url = URL(string: baseURL) else {
            isTranslating = false
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
            isTranslating = false
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isTranslating = false
                
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
                        self?.errorMessage = message
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
                    
                    let translatedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.success(translatedText))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
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

