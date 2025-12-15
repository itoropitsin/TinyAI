import Foundation
import Combine
import NaturalLanguage

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
    static let languageAutoSelection = "Auto"
    static let supportedLanguages: [String] = [
        "English", "Russian", "Spanish", "French", "German", "Italian",
        "Portuguese", "Chinese", "Japanese", "Korean", "Arabic", "Dutch",
        "Polish", "Turkish", "Swedish", "Norwegian", "Danish", "Finnish"
    ]

    @Published var apiKey: String = "" {
        didSet {
            if apiKey.isEmpty {
                KeychainStore.delete(service: keychainService, account: apiKeyDefaultsKey)
            } else {
                _ = KeychainStore.saveString(apiKey, service: keychainService, account: apiKeyDefaultsKey)
            }
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

    @Published var preferredTargetLanguage: String = "English" {
        didSet {
            let normalized = normalizedLanguageSelection(preferredTargetLanguage)
            if normalized != preferredTargetLanguage {
                preferredTargetLanguage = normalized
                return
            }
            UserDefaults.standard.set(preferredTargetLanguage, forKey: preferredTargetLanguageDefaultsKey)
        }
    }

    @Published var autoTranslateMainLanguage: String = "Russian" {
        didSet {
            let normalized = normalizedSupportedLanguage(autoTranslateMainLanguage, fallback: "Russian")
            if normalized != autoTranslateMainLanguage {
                autoTranslateMainLanguage = normalized
                return
            }
            UserDefaults.standard.set(autoTranslateMainLanguage, forKey: autoTranslateMainLanguageDefaultsKey)
        }
    }

    @Published var autoTranslateAdditionalLanguage: String = "English" {
        didSet {
            let normalized = normalizedSupportedLanguage(autoTranslateAdditionalLanguage, fallback: "English")
            if normalized != autoTranslateAdditionalLanguage {
                autoTranslateAdditionalLanguage = normalized
                return
            }
            UserDefaults.standard.set(autoTranslateAdditionalLanguage, forKey: autoTranslateAdditionalLanguageDefaultsKey)
        }
    }

    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    
    private let baseURLString = "https://api.openai.com/v1/chat/completions"
    private let keychainService: String
    private let session: URLSession
    private let jsonDecoder = JSONDecoder()

    private let apiKeyDefaultsKey = "OpenAIAPIKey"
    private let legacyModelDefaultsKey = "OpenAIModel"
    private let customActionsDefaultsKey = "CustomActionsV1"
    private let starredPrimaryDefaultsKey = "StarredPrimaryActionIdV1"
    private let starredSecondaryDefaultsKey = "StarredSecondaryActionIdV1"
    private let starredPrimarySelectionDefaultsKeyV2 = "StarredPrimarySelectionKeyV2"
    private let builtInTranslateModelDefaultsKey = "BuiltInTranslateModelV1"
    private let autoTranslateMainLanguageDefaultsKey = "AutoTranslateMainLanguageV1"
    private let autoTranslateAdditionalLanguageDefaultsKey = "AutoTranslateAdditionalLanguageV1"
    private let preferredTargetLanguageDefaultsKey = "PreferredTargetLanguageV1"
    
    init() {
        keychainService = Bundle.main.bundleIdentifier ?? "TinyAI"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)

        if let savedKey = KeychainStore.loadString(service: keychainService, account: apiKeyDefaultsKey) {
            apiKey = savedKey
        } else if let legacySavedKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) {
            apiKey = legacySavedKey
            _ = KeychainStore.saveString(legacySavedKey, service: keychainService, account: apiKeyDefaultsKey)
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        }

        if let savedModelRaw = UserDefaults.standard.string(forKey: builtInTranslateModelDefaultsKey),
           let savedModel = OpenAIModel(rawValue: savedModelRaw) {
            builtInTranslateModel = savedModel
        } else {
            builtInTranslateModel = resolveLegacyDefaultModel()
        }

        preferredTargetLanguage = normalizedLanguageSelection(
            UserDefaults.standard.string(forKey: preferredTargetLanguageDefaultsKey) ?? preferredTargetLanguage
        )

        autoTranslateMainLanguage = normalizedSupportedLanguage(
            UserDefaults.standard.string(forKey: autoTranslateMainLanguageDefaultsKey) ?? autoTranslateMainLanguage,
            fallback: "Russian"
        )
        autoTranslateAdditionalLanguage = normalizedSupportedLanguage(
            UserDefaults.standard.string(forKey: autoTranslateAdditionalLanguageDefaultsKey) ?? autoTranslateAdditionalLanguage,
            fallback: "English"
        )

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

    func saveAutoTranslateMainLanguage(_ language: String) {
        autoTranslateMainLanguage = normalizedSupportedLanguage(language, fallback: "Russian")
    }

    func saveAutoTranslateAdditionalLanguage(_ language: String) {
        autoTranslateAdditionalLanguage = normalizedSupportedLanguage(language, fallback: "English")
    }

    func resolveTargetLanguage(for text: String, selectedLanguage: String) -> String {
        guard selectedLanguage == Self.languageAutoSelection else {
            return selectedLanguage
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return autoTranslateMainLanguage
        }

        let main = autoTranslateMainLanguage
        let additional = autoTranslateAdditionalLanguage
        guard main != additional else {
            return main
        }

        guard let detected = detectDominantLanguage(for: trimmed) else {
            return main
        }

        if matches(displayName: main, detectedLanguage: detected) {
            return additional
        }

        if matches(displayName: additional, detectedLanguage: detected) {
            return main
        }

        return main
    }

    private func normalizedSupportedLanguage(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard Self.supportedLanguages.contains(trimmed) else { return fallback }
        return trimmed
    }

    private func normalizedLanguageSelection(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "English" }
        if trimmed == Self.languageAutoSelection {
            return trimmed
        }
        return normalizedSupportedLanguage(trimmed, fallback: "English")
    }

    private func detectDominantLanguage(for text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage, language != .undetermined {
            return language
        }

        let hasCyrillic = text.unicodeScalars.contains { scalar in
            (0x0400...0x04FF).contains(Int(scalar.value)) || (0x0500...0x052F).contains(Int(scalar.value))
        }
        let hasLatin = text.unicodeScalars.contains { scalar in
            (0x0041...0x005A).contains(Int(scalar.value)) || (0x0061...0x007A).contains(Int(scalar.value))
        }

        if hasCyrillic && !hasLatin {
            return .russian
        }
        if hasLatin && !hasCyrillic {
            return .english
        }

        return nil
    }

    private func matches(displayName: String, detectedLanguage: NLLanguage) -> Bool {
        switch displayName {
        case "English":
            return detectedLanguage == .english
        case "Russian":
            return detectedLanguage == .russian
        case "Spanish":
            return detectedLanguage == .spanish
        case "French":
            return detectedLanguage == .french
        case "German":
            return detectedLanguage == .german
        case "Italian":
            return detectedLanguage == .italian
        case "Portuguese":
            return detectedLanguage == .portuguese
        case "Chinese":
            return detectedLanguage == .simplifiedChinese || detectedLanguage == .traditionalChinese
        case "Japanese":
            return detectedLanguage == .japanese
        case "Korean":
            return detectedLanguage == .korean
        case "Arabic":
            return detectedLanguage == .arabic
        case "Dutch":
            return detectedLanguage == .dutch
        case "Polish":
            return detectedLanguage == .polish
        case "Turkish":
            return detectedLanguage == .turkish
        case "Swedish":
            return detectedLanguage == .swedish
        case "Norwegian":
            return detectedLanguage == .norwegian
        case "Danish":
            return detectedLanguage == .danish
        case "Finnish":
            return detectedLanguage == .finnish
        default:
            return false
        }
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

        customActions[0].title = "Grammar"
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
        if (title == "Translate" || title == "Перевод") && prompt.contains("You are a professional translator") {
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
            ((title == "Translate" || title == "Перевод") && prompt.contains("You are a professional translator"))
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
                ((secondTitle == "Grammar" || secondTitle == "Грамматика") && secondPrompt.contains("You are an expert editor"))
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

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct APIErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String
        }
        let error: APIError
    }

    @discardableResult
    private func performChatCompletion(requestBody: [String: Any], completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !apiKey.isEmpty else {
            completion(.failure(TranslationError.apiKeyMissing))
            return nil
        }

        guard let url = URL(string: baseURLString) else {
            completion(.failure(TranslationError.invalidURL))
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return nil
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode

            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    completion(.failure(error))
                    return
                }

                guard let data else {
                    completion(.failure(TranslationError.noData))
                    return
                }

                if let statusCode, statusCode != 200 {
                    if let apiError = try? self.jsonDecoder.decode(APIErrorResponse.self, from: data) {
                        completion(.failure(TranslationError.apiError(apiError.error.message)))
                    } else {
                        completion(.failure(TranslationError.httpError(statusCode)))
                    }
                    return
                }

                do {
                    let decoded = try self.jsonDecoder.decode(ChatCompletionResponse.self, from: data)
                    guard let content = decoded.choices.first?.message.content else {
                        completion(.failure(TranslationError.invalidResponse))
                        return
                    }
                    completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
                } catch {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
        return task
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
	                if self?.isCancellationError(error) == true {
	                    completion(result)
	                    return
	                }
	                if let localizedError = error as? LocalizedError {
	                    self?.errorMessage = localizedError.errorDescription
	                } else {
	                    self?.errorMessage = error.localizedDescription
	                }
	                completion(result)
	            }
	        }
	    }

    @discardableResult
    func translateText(text: String, targetLanguage: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildRequestBody(text: text, targetLanguage: targetLanguage, model: modelToUse)
        return performChatCompletion(requestBody: requestBody, completion: completion)
    }

    @discardableResult
    func translateHTML(html: String, targetLanguage: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildHTMLTranslateRequestBody(html: html, targetLanguage: targetLanguage, model: modelToUse)
        return performChatCompletion(requestBody: requestBody, completion: completion)
    }

    @discardableResult
    func grammarFix(text: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildGrammarFixRequestBody(text: text, model: modelToUse)
        return performChatCompletion(requestBody: requestBody, completion: completion)
    }

    @discardableResult
	    func runCustomAction(text: String, prompt: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            completion(.failure(TranslationError.customPromptMissing))
            return nil
        }

        isTranslating = true
        errorMessage = nil

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildCustomActionRequestBody(text: trimmedText, prompt: trimmedPrompt, model: modelToUse)
	        return performChatCompletion(requestBody: requestBody) { [weak self] result in
	            self?.isTranslating = false
	            switch result {
	            case .success:
	                completion(result)
	            case .failure(let error):
	                if self?.isCancellationError(error) == true {
	                    completion(result)
	                    return
	                }
	                if let localizedError = error as? LocalizedError {
	                    self?.errorMessage = localizedError.errorDescription
	                } else {
	                    self?.errorMessage = error.localizedDescription
	                }
	                completion(result)
	            }
	        }
	    }

	    private func isCancellationError(_ error: Error) -> Bool {
	        let nsError = error as NSError
	        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
	    }

    @discardableResult
    func grammarFixHTML(html: String, modelOverride: OpenAIModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let modelToUse = modelOverride ?? .gpt5Mini
        let requestBody = buildHTMLGrammarFixRequestBody(html: html, model: modelToUse)
        return performChatCompletion(requestBody: requestBody, completion: completion)
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
            return "API key is not set"
        case .emptyText:
            return "Text to translate is empty"
        case .customPromptMissing:
            return "Custom prompt is not set"
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received from the server"
        case .invalidResponse:
            return "Invalid response format"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return message
        }
    }
}
