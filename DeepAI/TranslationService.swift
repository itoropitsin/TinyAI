import Foundation
import Combine

enum OpenAIModel: String, CaseIterable, Identifiable, Codable {
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

struct CustomAction: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var prompt: String
    var model: OpenAIModel

    init(id: UUID = UUID(), title: String = "", prompt: String = "", model: OpenAIModel = .gpt5Mini) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case prompt
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        prompt = (try? container.decode(String.self, forKey: .prompt)) ?? ""
        model = (try? container.decode(OpenAIModel.self, forKey: .model)) ?? .gpt5Mini
    }
}

class TranslationService: ObservableObject {
    @Published var apiKey: String = "" {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: apiKeyDefaultsKey)
        }
    }

    @Published var customActions: [CustomAction] = [] {
        didSet {
            saveCustomActionsToDefaults(customActions)
        }
    }

    static let builtInTranslateSelectionKey = "builtin_translate"

    @Published var starredPrimarySelectionKey: String = TranslationService.builtInTranslateSelectionKey {
        didSet {
            saveStarredPrimarySelectionKeyToDefaults(starredPrimarySelectionKey)
        }
    }

    @Published var starredSecondaryActionId: UUID? {
        didSet {
            saveStarredActionIdToDefaults(starredSecondaryActionId, key: starredSecondaryDefaultsKey)
        }
    }

    @Published var builtInTranslateModel: OpenAIModel = .gpt5Mini {
        didSet {
            UserDefaults.standard.set(builtInTranslateModel.rawValue, forKey: builtInTranslateModelDefaultsKey)
        }
    }

    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    private let apiKeyDefaultsKey = "OpenAIAPIKey"
    private let legacyModelDefaultsKey = "OpenAIModel"
    private let customActionsDefaultsKey = "CustomActionsV1"
    private let starredPrimaryDefaultsKey = "StarredPrimaryActionIdV1"
    private let starredSecondaryDefaultsKey = "StarredSecondaryActionIdV1"
    private let starredPrimarySelectionDefaultsKeyV2 = "StarredPrimarySelectionKeyV2"
    private let builtInTranslateModelDefaultsKey = "BuiltInTranslateModelV1"
    
    init() {
        if let savedKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) {
            apiKey = savedKey
        }

        if let savedModelRaw = UserDefaults.standard.string(forKey: builtInTranslateModelDefaultsKey),
           let savedModel = OpenAIModel(rawValue: savedModelRaw) {
            builtInTranslateModel = savedModel
        } else {
            builtInTranslateModel = resolveLegacyDefaultModel()
        }

        let loadedActions = loadCustomActionsFromDefaults()
        if let loadedActions {
            customActions = normalizeCustomActions(loadedActions)
        } else {
            customActions = normalizeCustomActions([])
        }

        if loadedActions == nil {
            applyBuiltInDefaultsIfNeeded(force: true)
        } else {
            applyBuiltInDefaultsIfNeeded(force: false)
        }

        starredPrimarySelectionKey = loadOrMigrateStarredPrimarySelectionKey(legacyPrimaryId: loadStarredActionIdFromDefaults(key: starredPrimaryDefaultsKey))
        starredSecondaryActionId = loadStarredActionIdFromDefaults(key: starredSecondaryDefaultsKey)

        clearLegacyDefaultTranslationActionIfPresent()
        applyBuiltInDefaultsIfNeeded(force: false)
        normalizeStarredActionIds()
    }
    
    func saveAPIKey(_ key: String) {
        apiKey = key
    }

    func saveCustomActions(_ actions: [CustomAction]) {
        customActions = normalizeCustomActions(actions)
        applyBuiltInDefaultsIfNeeded(force: false)
        clearLegacyDefaultTranslationActionIfPresent()
        normalizeStarredActionIds()
    }

    func saveStarredPrimarySelectionKey(_ key: String) {
        starredPrimarySelectionKey = key
        normalizeStarredActionIds()
    }

    func saveStarredSecondaryActionId(_ id: UUID?) {
        starredSecondaryActionId = id
        normalizeStarredActionIds()
    }

    func saveBuiltInTranslateModel(_ model: OpenAIModel) {
        builtInTranslateModel = model
    }

    private func normalizeCustomActions(_ actions: [CustomAction]) -> [CustomAction] {
        var result = Array(actions.prefix(5))
        while result.count < 5 {
            result.append(CustomAction())
        }
        return result
    }

    private func normalizeStarredActionIds() {
        if starredPrimarySelectionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            starredPrimarySelectionKey = TranslationService.builtInTranslateSelectionKey
        }

        if starredPrimarySelectionKey != TranslationService.builtInTranslateSelectionKey {
            if UUID(uuidString: starredPrimarySelectionKey) == nil {
                starredPrimarySelectionKey = TranslationService.builtInTranslateSelectionKey
            } else if customActions.first(where: { $0.id.uuidString == starredPrimarySelectionKey }) == nil {
                starredPrimarySelectionKey = customActions.first?.id.uuidString ?? TranslationService.builtInTranslateSelectionKey
            }
        }

        if starredSecondaryActionId == nil {
            starredSecondaryActionId = customActions.first?.id
        }

        if starredPrimarySelectionKey != TranslationService.builtInTranslateSelectionKey,
           let primary = UUID(uuidString: starredPrimarySelectionKey),
           let secondary = starredSecondaryActionId,
           primary == secondary {
            starredSecondaryActionId = customActions.first(where: { $0.id != primary })?.id
        }
    }

    private func applyBuiltInDefaultsIfNeeded(force: Bool) {
        guard customActions.count >= 1 else {
            return
        }

        let defaultModel = resolveLegacyDefaultModel()

        let hasAnyConfigured = customActions.contains { action in
            !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !force && hasAnyConfigured {
            return
        }

        let defaultGrammarPrompt = """
You are an expert editor.
Fix punctuation, grammar, and awkward or unclear constructions while preserving the original meaning and writing style.

Rules:
- Keep the original language.
- Preserve tone (formal/informal), voice, and intent.
- Preserve formatting: line breaks, lists, numbering, emojis, code blocks, and URLs.
- Do not add explanations, notes, or commentary.
- Output only the corrected version of the text.
"""

        customActions[0].title = "Грамматика"
        customActions[0].prompt = defaultGrammarPrompt
        customActions[0].model = defaultModel
    }

    private func resolveLegacyDefaultModel() -> OpenAIModel {
        if let savedLegacyModelRaw = UserDefaults.standard.string(forKey: legacyModelDefaultsKey),
           let savedModel = OpenAIModel(rawValue: savedLegacyModelRaw) {
            return savedModel
        }
        return .gpt5Mini
    }

    private func loadOrMigrateStarredPrimarySelectionKey(legacyPrimaryId: UUID?) -> String {
        if let v2 = UserDefaults.standard.string(forKey: starredPrimarySelectionDefaultsKeyV2) {
            return v2
        }

        let migrated: String
        if let legacyPrimaryId {
            if isLegacyDefaultTranslationActionId(legacyPrimaryId) {
                migrated = TranslationService.builtInTranslateSelectionKey
            } else {
                migrated = legacyPrimaryId.uuidString
            }
        } else {
            migrated = TranslationService.builtInTranslateSelectionKey
        }

        saveStarredPrimarySelectionKeyToDefaults(migrated)
        return migrated
    }

    private func saveStarredPrimarySelectionKeyToDefaults(_ key: String) {
        UserDefaults.standard.set(key, forKey: starredPrimarySelectionDefaultsKeyV2)
    }

    private func isLegacyDefaultTranslationActionId(_ id: UUID) -> Bool {
        guard let first = customActions.first, first.id == id else {
            return false
        }
        let title = first.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = first.prompt
        if title == "Перевод" && prompt.contains("You are a professional translator") {
            return true
        }
        if prompt.contains("Translate from Auto-detect") && prompt.contains("{{targetLanguage}}") {
            return true
        }
        return false
    }

    private func clearLegacyDefaultTranslationActionIfPresent() {
        guard customActions.count >= 1 else {
            return
        }
        let title = customActions[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = customActions[0].prompt

        let looksLikeLegacyDefaultTranslation =
            (title == "Перевод" && prompt.contains("You are a professional translator"))
            || (prompt.contains("Translate from Auto-detect") && prompt.contains("{{targetLanguage}}"))

        guard looksLikeLegacyDefaultTranslation else {
            return
        }

        customActions[0].title = ""
        customActions[0].prompt = ""

        if customActions.count >= 2 {
            let secondTitle = customActions[1].title.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondPrompt = customActions[1].prompt
            let looksLikeLegacyDefaultGrammar =
                (secondTitle == "Грамматика" && secondPrompt.contains("You are an expert editor"))
                || (secondPrompt.contains("Fix punctuation, grammar") && secondPrompt.contains("Output only the corrected version"))

            if looksLikeLegacyDefaultGrammar {
                customActions[0] = customActions[1]
                customActions[1] = CustomAction()
            }
        }

        let hasAnyConfigured = customActions.contains { action in
            !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !hasAnyConfigured {
            applyBuiltInDefaultsIfNeeded(force: true)
        }
    }

    var isStarredPrimaryBuiltInTranslate: Bool {
        starredPrimarySelectionKey == TranslationService.builtInTranslateSelectionKey
    }

    func starredPrimaryCustomAction() -> CustomAction? {
        guard !isStarredPrimaryBuiltInTranslate,
              let id = UUID(uuidString: starredPrimarySelectionKey) else {
            return nil
        }
        return customActions.first(where: { $0.id == id })
    }

    private func loadCustomActionsFromDefaults() -> [CustomAction]? {
        guard let data = UserDefaults.standard.data(forKey: customActionsDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode([CustomAction].self, from: data)
    }

    private func saveCustomActionsToDefaults(_ actions: [CustomAction]) {
        guard let data = try? JSONEncoder().encode(actions) else {
            return
        }
        UserDefaults.standard.set(data, forKey: customActionsDefaultsKey)
    }

    private func loadStarredActionIdFromDefaults(key: String) -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private func saveStarredActionIdToDefaults(_ id: UUID?, key: String) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func buildHTMLTranslateRequestBody(html: String, targetLanguage: String, model: OpenAIModel) -> [String: Any] {
        let systemPrompt = """
You are a professional translator.

Input is HTML.
Translate from Auto-detect to \(targetLanguage) naturally and clearly.

Rules:
- Preserve the HTML structure exactly: keep tags, attributes, links, code tags, lists, and nesting.
- Translate only the human-readable text content (text nodes).
- Preserve whitespace and line breaks as represented in the HTML.
- Do not add explanations, notes, or commentary.
- Output only valid HTML (no Markdown, no code fences).
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
                    "content": html
                ]
            ],
            "max_completion_tokens": 1500
        ]

        switch model {
        case .gpt52:
            requestBody["temperature"] = 0.2
        case .gpt5Mini, .gpt5Nano:
            break
        }

        return requestBody
    }

    private func buildCustomActionRequestBody(text: String, prompt: String, model: OpenAIModel) -> [String: Any] {
        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                [
                    "role": "system",
                    "content": prompt
                ],
                [
                    "role": "user",
                    "content": text
                ]
            ],
            "max_completion_tokens": 1500
        ]

        switch model {
        case .gpt52:
            requestBody["temperature"] = 0.2
        case .gpt5Mini, .gpt5Nano:
            break
        }

        return requestBody
    }

    private func buildHTMLGrammarFixRequestBody(html: String, model: OpenAIModel) -> [String: Any] {
        let systemPrompt = """
You are an expert editor.

Input is HTML.
Fix punctuation, grammar, and awkward or unclear constructions while preserving the original meaning and writing style.

Rules:
- Keep the original language.
- Preserve the HTML structure exactly: keep tags, attributes, links, code tags, lists, and nesting.
- Edit only the human-readable text content (text nodes).
- Preserve whitespace and line breaks as represented in the HTML.
- Do not add explanations, notes, or commentary.
- Output only valid HTML (no Markdown, no code fences).
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
                    "content": html
                ]
            ],
            "max_completion_tokens": 1500
        ]

        switch model {
        case .gpt52:
            requestBody["temperature"] = 0.2
        case .gpt5Mini, .gpt5Nano:
            break
        }

        return requestBody
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

        let modelToUse = modelOverride ?? .gpt5Mini
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

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildRequestBody(text: text, targetLanguage: targetLanguage, model: modelToUse)
        performChatCompletion(requestBody: requestBody, completion: completion)
    }

    func translateHTML(html: String, targetLanguage: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildHTMLTranslateRequestBody(html: html, targetLanguage: targetLanguage, model: modelToUse)
        performChatCompletion(requestBody: requestBody, completion: completion)
    }

    func grammarFix(text: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildGrammarFixRequestBody(text: text, model: modelToUse)
        performChatCompletion(requestBody: requestBody, completion: completion)
    }

    func runCustomAction(text: String, prompt: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            completion(.failure(TranslationError.customPromptMissing))
            return
        }

        isTranslating = true
        errorMessage = nil

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildCustomActionRequestBody(text: trimmedText, prompt: trimmedPrompt, model: modelToUse)
        performChatCompletion(requestBody: requestBody) { [weak self] result in
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

    func grammarFixHTML(html: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildHTMLGrammarFixRequestBody(html: html, model: modelToUse)
        performChatCompletion(requestBody: requestBody, completion: completion)
    }
}

enum TranslationError: LocalizedError {
    case apiKeyMissing
    case emptyText
    case customPromptMissing
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
        case .customPromptMissing:
            return "Кастомный промпт не задан"
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

