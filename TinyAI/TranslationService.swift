import Foundation
import Combine
import NaturalLanguage

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case openAI = "openai"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Google Gemini"
        }
    }

    var keychainAccount: String {
        switch self {
        case .openAI:
            return "OpenAIAPIKey"
        case .gemini:
            return "GeminiAPIKey"
        }
    }
}

struct LLMModel: Codable, Hashable, Identifiable {
    var provider: LLMProvider
    var name: String

    var id: String { key }
    var key: String { "\(provider.rawValue):\(name)" }
}

struct LLMModelEntry: Codable, Hashable, Identifiable {
    var model: LLMModel
    var displayName: String

    var id: String { model.key }

    var displayNameWithProvider: String {
        "\(model.provider.displayName): \(displayName)"
    }
}

struct LLMKeyValidationError: LocalizedError, Equatable {
    let provider: LLMProvider
    let statusCode: Int?
    let message: String

    var errorDescription: String? {
        if let statusCode {
            return "\(provider.displayName) key validation failed (\(statusCode)): \(message)"
        }
        return "\(provider.displayName) key validation failed: \(message)"
    }
}

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
    var model: LLMModel

    init(id: UUID = UUID(), title: String = "", prompt: String = "", model: LLMModel = TranslationService.defaultModel) {
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
        if let decoded = try? container.decode(LLMModel.self, forKey: .model) {
            model = decoded
        } else if let legacy = try? container.decode(OpenAIModel.self, forKey: .model) {
            model = LLMModel(provider: .openAI, name: legacy.rawValue)
        } else {
            model = TranslationService.defaultModel
        }
    }
}

class TranslationService: ObservableObject {
    static let languageAutoSelection = "Auto"
    static let supportedLanguages: [String] = [
        "English", "Russian", "Spanish", "French", "German", "Italian",
        "Portuguese", "Chinese", "Japanese", "Korean", "Arabic", "Dutch",
        "Polish", "Turkish", "Swedish", "Norwegian", "Danish", "Finnish"
    ]
    static let defaultModel = LLMModel(provider: .openAI, name: OpenAIModel.gpt5Mini.rawValue)

    @Published var apiKey: String = "" {
        didSet {
            persistAPIKey(apiKey, provider: .openAI)
        }
    }

    @Published var geminiAPIKey: String = "" {
        didSet {
            persistAPIKey(geminiAPIKey, provider: .gemini)
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

    @Published var builtInTranslateModel: LLMModel = TranslationService.defaultModel {
        didSet {
            UserDefaults.standard.set(builtInTranslateModel.key, forKey: builtInTranslateModelDefaultsKey)
        }
    }

    @Published private(set) var llmModels: [LLMModelEntry] = []
    @Published var llmModelVisibility: [String: Bool] = [:] {
        didSet {
            saveModelVisibilityToDefaults(llmModelVisibility)
        }
    }
    @Published var llmModelAvailability: [String: Bool] = [:] {
        didSet {
            saveModelAvailabilityToDefaults(llmModelAvailability)
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
    
    private let openAIChatCompletionsURLString = "https://api.openai.com/v1/chat/completions"
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
    private let llmModelsDefaultsKey = "LLMModelsV1"
    private let llmModelVisibilityDefaultsKey = "LLMModelVisibilityV1"
    private let llmModelAvailabilityDefaultsKey = "LLMModelAvailabilityV1"
    
    init() {
        keychainService = Bundle.main.bundleIdentifier ?? "TinyAI"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)

        apiKey = loadOrMigrateAPIKey(provider: .openAI)
        geminiAPIKey = loadOrMigrateAPIKey(provider: .gemini)

        builtInTranslateModel = loadBuiltInTranslateModel()

        llmModels = loadModelsFromDefaults()
        llmModelVisibility = loadModelVisibilityFromDefaults()
        llmModelAvailability = loadModelAvailabilityFromDefaults()
        normalizeModelsAndVisibility()

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

    func apiKey(for provider: LLMProvider) -> String {
        switch provider {
        case .openAI:
            return apiKey
        case .gemini:
            return geminiAPIKey
        }
    }

    func hasAPIKey(for provider: LLMProvider) -> Bool {
        !apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func validateAndSaveAPIKey(_ key: String, for provider: LLMProvider) async -> Result<Void, LLMKeyValidationError> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            setAPIKey("", for: provider)
            return .success(())
        }

        let result = await validateAPIKey(trimmed, for: provider)
        switch result {
        case .success:
            setAPIKey(trimmed, for: provider)
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    @MainActor
    func refreshModels(for provider: LLMProvider) async -> Result<Void, LLMKeyValidationError> {
        let key = apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return .failure(LLMKeyValidationError(provider: provider, statusCode: nil, message: "API key is not set"))
        }

        do {
            let fetched = try await fetchModels(provider: provider, apiKey: key)
            applyFetchedModels(fetched, for: provider)
            return .success(())
        } catch let error as LLMKeyValidationError {
            return .failure(error)
        } catch {
            return .failure(LLMKeyValidationError(provider: provider, statusCode: nil, message: error.localizedDescription))
        }
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

    func saveBuiltInTranslateModel(_ model: LLMModel) {
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

        let defaultModel = resolveLegacyDefaultLLMModel()

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

    private func resolveLegacyDefaultLLMModel() -> LLMModel {
        LLMModel(provider: .openAI, name: resolveLegacyDefaultModel().rawValue)
    }

    private func persistAPIKey(_ value: String, provider: LLMProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(service: keychainService, account: provider.keychainAccount)
        } else {
            _ = KeychainStore.saveString(trimmed, service: keychainService, account: provider.keychainAccount)
        }
    }

    private func loadOrMigrateAPIKey(provider: LLMProvider) -> String {
        if let savedKey = KeychainStore.loadString(service: keychainService, account: provider.keychainAccount) {
            return savedKey
        }

        if provider == .openAI, let legacySavedKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) {
            _ = KeychainStore.saveString(legacySavedKey, service: keychainService, account: provider.keychainAccount)
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
            return legacySavedKey
        }

        return ""
    }

    private func setAPIKey(_ key: String, for provider: LLMProvider) {
        switch provider {
        case .openAI:
            apiKey = key
        case .gemini:
            geminiAPIKey = key
        }
    }

    private func loadBuiltInTranslateModel() -> LLMModel {
        if let savedKey = UserDefaults.standard.string(forKey: builtInTranslateModelDefaultsKey),
           let parsed = parseModelKey(savedKey) {
            return parsed
        }

        if let savedLegacyModelRaw = UserDefaults.standard.string(forKey: builtInTranslateModelDefaultsKey),
           let legacy = OpenAIModel(rawValue: savedLegacyModelRaw) {
            return LLMModel(provider: .openAI, name: legacy.rawValue)
        }

        return resolveLegacyDefaultLLMModel()
    }

    private func parseModelKey(_ key: String) -> LLMModel? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let provider = LLMProvider(rawValue: parts[0]),
              !parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return LLMModel(provider: provider, name: parts[1])
    }

    var modelsForActionsPicker: [LLMModelEntry] {
        let filtered = llmModels.filter { llmModelVisibility[$0.model.key] ?? true }
        return filtered.sorted { $0.displayNameWithProvider.localizedCaseInsensitiveCompare($1.displayNameWithProvider) == .orderedAscending }
    }

    func modelsForActionsPickerIncluding(_ selection: LLMModel) -> [LLMModelEntry] {
        var list = modelsForActionsPicker
        if !list.contains(where: { $0.model == selection }) {
            let fallbackName = llmModels.first(where: { $0.model == selection })?.displayName ?? selection.name
            list.insert(LLMModelEntry(model: selection, displayName: fallbackName), at: 0)
        }
        return list
    }

    func setModelVisible(_ model: LLMModel, visible: Bool) {
        llmModelVisibility[model.key] = visible
    }

    func isModelVisible(_ model: LLMModel) -> Bool {
        llmModelVisibility[model.key] ?? true
    }

    func isModelAvailable(_ model: LLMModel) -> Bool {
        llmModelAvailability[model.key] ?? true
    }

    func replacementCandidates(excluding model: LLMModel) -> [LLMModelEntry] {
        llmModels
            .filter { $0.model != model }
            .filter { isModelAvailable($0.model) }
            .sorted { $0.displayNameWithProvider.localizedCaseInsensitiveCompare($1.displayNameWithProvider) == .orderedAscending }
    }

    func deleteModel(_ model: LLMModel) {
        llmModels.removeAll { $0.model == model }
        llmModelVisibility.removeValue(forKey: model.key)
        llmModelAvailability.removeValue(forKey: model.key)

        if builtInTranslateModel == model {
            builtInTranslateModel = Self.defaultModel
        }

        if customActions.contains(where: { $0.model == model }) {
            let updated = customActions.map { action -> CustomAction in
                if action.model == model {
                    var copy = action
                    copy.model = Self.defaultModel
                    return copy
                }
                return action
            }
            customActions = updated
        }

        saveModelsToDefaults(llmModels)
        saveModelVisibilityToDefaults(llmModelVisibility)
        saveModelAvailabilityToDefaults(llmModelAvailability)
    }

    private func loadModelsFromDefaults() -> [LLMModelEntry] {
        guard let data = UserDefaults.standard.data(forKey: llmModelsDefaultsKey),
              let decoded = try? JSONDecoder().decode([LLMModelEntry].self, from: data) else {
            return OpenAIModel.allCases.map { legacy in
                LLMModelEntry(model: LLMModel(provider: .openAI, name: legacy.rawValue), displayName: legacy.displayName)
            }
        }
        return decoded
    }

    private func saveModelsToDefaults(_ models: [LLMModelEntry]) {
        guard let data = try? JSONEncoder().encode(models) else {
            return
        }
        UserDefaults.standard.set(data, forKey: llmModelsDefaultsKey)
    }

    private func loadModelVisibilityFromDefaults() -> [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: llmModelVisibilityDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveModelVisibilityToDefaults(_ map: [String: Bool]) {
        guard let data = try? JSONEncoder().encode(map) else {
            return
        }
        UserDefaults.standard.set(data, forKey: llmModelVisibilityDefaultsKey)
    }

    private func loadModelAvailabilityFromDefaults() -> [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: llmModelAvailabilityDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveModelAvailabilityToDefaults(_ map: [String: Bool]) {
        guard let data = try? JSONEncoder().encode(map) else {
            return
        }
        UserDefaults.standard.set(data, forKey: llmModelAvailabilityDefaultsKey)
    }

    private func normalizeModelsAndVisibility() {
        if llmModels.isEmpty {
            llmModels = OpenAIModel.allCases.map { legacy in
                LLMModelEntry(model: LLMModel(provider: .openAI, name: legacy.rawValue), displayName: legacy.displayName)
            }
        }

        var visibility = llmModelVisibility
        var availability = llmModelAvailability
        for entry in llmModels {
            if visibility[entry.model.key] == nil {
                visibility[entry.model.key] = true
            }
            if availability[entry.model.key] == nil {
                availability[entry.model.key] = true
            }
        }
        llmModelVisibility = visibility
        llmModelAvailability = availability

        llmModels = dedupModels(llmModels)
        saveModelsToDefaults(llmModels)
    }

    private func dedupModels(_ models: [LLMModelEntry]) -> [LLMModelEntry] {
        var seen: Set<String> = []
        var result: [LLMModelEntry] = []
        for entry in models {
            if seen.insert(entry.model.key).inserted {
                result.append(entry)
            }
        }
        return result
    }

    private func applyFetchedModels(_ fetched: [LLMModelEntry], for provider: LLMProvider) {
        let existing = llmModels
        let existingKeys = Set(existing.map(\.model.key))

        var visibility = llmModelVisibility
        for entry in fetched where !existingKeys.contains(entry.model.key) {
            visibility[entry.model.key] = false
        }
        llmModelVisibility = visibility

        llmModels = dedupModels(existing + fetched)

        let fetchedKeys = Set(fetched.map(\.model.key))
        var availability = llmModelAvailability
        for entry in llmModels where entry.model.provider == provider {
            availability[entry.model.key] = fetchedKeys.contains(entry.model.key)
        }
        llmModelAvailability = availability

        saveModelsToDefaults(llmModels)
    }

    private func validateAPIKey(_ key: String, for provider: LLMProvider) async -> Result<Void, LLMKeyValidationError> {
        do {
            _ = try await fetchModels(provider: provider, apiKey: key)
            return .success(())
        } catch let error as LLMKeyValidationError {
            return .failure(error)
        } catch {
            return .failure(LLMKeyValidationError(provider: provider, statusCode: nil, message: error.localizedDescription))
        }
    }

    private func fetchModels(provider: LLMProvider, apiKey: String) async throws -> [LLMModelEntry] {
        switch provider {
        case .openAI:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .gemini:
            return try await fetchGeminiModels(apiKey: apiKey)
        }
    }

    private struct OpenAIModelsResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [LLMModelEntry] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw LLMKeyValidationError(provider: .openAI, statusCode: nil, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard statusCode == 200 else {
            let message = parseOpenAIErrorMessage(from: data) ?? "HTTP error"
            throw LLMKeyValidationError(provider: .openAI, statusCode: statusCode, message: message)
        }

        let decoded = try jsonDecoder.decode(OpenAIModelsResponse.self, from: data)
        let entries = decoded.data
            .map { LLMModelEntry(model: LLMModel(provider: .openAI, name: $0.id), displayName: $0.id) }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        return entries
    }

    private struct GeminiModelsResponse: Decodable {
        struct Model: Decodable {
            let name: String
            let displayName: String?
            let supportedGenerationMethods: [String]?
        }
        let models: [Model]?
    }

    private struct GeminiErrorResponse: Decodable {
        struct GeminiError: Decodable {
            let code: Int?
            let message: String?
            let status: String?
        }
        let error: GeminiError
    }

    private func fetchGeminiModels(apiKey: String) async throws -> [LLMModelEntry] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            throw LLMKeyValidationError(provider: .gemini, statusCode: nil, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard statusCode == 200 else {
            let message = parseGeminiErrorMessage(from: data) ?? "HTTP error"
            throw LLMKeyValidationError(provider: .gemini, statusCode: statusCode, message: message)
        }

        let decoded = try jsonDecoder.decode(GeminiModelsResponse.self, from: data)
        let rawModels: [GeminiModelsResponse.Model] = decoded.models ?? []
        let mapped: [LLMModelEntry] = rawModels
            .filter { ($0.supportedGenerationMethods ?? []).contains("generateContent") }
            .map { model in
                let id = model.name.replacingOccurrences(of: "models/", with: "")
                return LLMModelEntry(model: LLMModel(provider: .gemini, name: id), displayName: model.displayName ?? id)
            }
        let entries = mapped.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return entries
    }

    private func parseOpenAIErrorMessage(from data: Data) -> String? {
        if let apiError = try? jsonDecoder.decode(APIErrorResponse.self, from: data) {
            return apiError.error.message
        }
        return nil
    }

    private func parseGeminiErrorMessage(from data: Data) -> String? {
        if let apiError = try? jsonDecoder.decode(GeminiErrorResponse.self, from: data) {
            let status = apiError.error.status ?? "Error"
            let message = apiError.error.message ?? "Unknown error"
            return "\(status): \(message)"
        }
        return nil
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

    private func translateSystemPrompt(targetLanguage: String) -> String {
        """
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
    }

    private func translateHTMLSystemPrompt(targetLanguage: String) -> String {
        """
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
    }

    private func grammarSystemPrompt() -> String {
        """
You are an expert editor.
Fix punctuation, grammar, and awkward or unclear constructions while preserving the original meaning and writing style.

Rules:
- Keep the original language.
- Preserve tone (formal/informal), voice, and intent.
- Preserve formatting: line breaks, lists, numbering, emojis, code blocks, and URLs.
- Do not add explanations, notes, or commentary.
- Output only the corrected version of the text.
"""
    }

    private func grammarHTMLSystemPrompt() -> String {
        """
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
    }

    private func buildHTMLTranslateRequestBody(html: String, targetLanguage: String, modelName: String) -> [String: Any] {
        let systemPrompt = translateHTMLSystemPrompt(targetLanguage: targetLanguage)

        var requestBody: [String: Any] = [
            "model": modelName,
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

        if modelName == OpenAIModel.gpt52.rawValue {
            requestBody["temperature"] = 0.2
        }

        return requestBody
    }

    private func buildCustomActionRequestBody(text: String, prompt: String, modelName: String) -> [String: Any] {
        var requestBody: [String: Any] = [
            "model": modelName,
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

        if modelName == OpenAIModel.gpt52.rawValue {
            requestBody["temperature"] = 0.2
        }

        return requestBody
    }

    private func buildHTMLGrammarFixRequestBody(html: String, modelName: String) -> [String: Any] {
        let systemPrompt = grammarHTMLSystemPrompt()

        var requestBody: [String: Any] = [
            "model": modelName,
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

        if modelName == OpenAIModel.gpt52.rawValue {
            requestBody["temperature"] = 0.2
        }

        return requestBody
    }

    private func buildRequestBody(text: String, targetLanguage: String, modelName: String) -> [String: Any] {
        let systemPrompt = translateSystemPrompt(targetLanguage: targetLanguage)

        var requestBody: [String: Any] = [
            "model": modelName,
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

        if modelName == OpenAIModel.gpt52.rawValue {
            requestBody["temperature"] = 0.3
        }

        return requestBody
    }

    private func buildGrammarFixRequestBody(text: String, modelName: String) -> [String: Any] {
        let systemPrompt = grammarSystemPrompt()

        var requestBody: [String: Any] = [
            "model": modelName,
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

        if modelName == OpenAIModel.gpt52.rawValue {
            requestBody["temperature"] = 0.2
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
    private func performOpenAIChatCompletion(apiKey: String, requestBody: [String: Any], completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !apiKey.isEmpty else {
            completion(.failure(TranslationError.apiKeyMissing))
            return nil
        }

        guard let url = URL(string: openAIChatCompletionsURLString) else {
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

    private struct GeminiGenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    @discardableResult
    private func performGeminiGenerateContent(apiKey: String, modelName: String, systemPrompt: String, userText: String, maxOutputTokens: Int, temperature: Double?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !apiKey.isEmpty else {
            completion(.failure(TranslationError.apiKeyMissing))
            return nil
        }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)") else {
            completion(.failure(TranslationError.invalidURL))
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var generationConfig: [String: Any] = [
            "maxOutputTokens": maxOutputTokens
        ]
        if let temperature {
            generationConfig["temperature"] = temperature
        }

        let requestBody: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": userText]
                    ]
                ]
            ],
            "generationConfig": generationConfig
        ]

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
                    if let apiError = try? self.jsonDecoder.decode(GeminiErrorResponse.self, from: data) {
                        let status = apiError.error.status ?? "Error"
                        let message = apiError.error.message ?? "Unknown error"
                        completion(.failure(TranslationError.apiError("\(status): \(message)")))
                    } else {
                        completion(.failure(TranslationError.httpError(statusCode)))
                    }
                    return
                }

                do {
                    let decoded = try self.jsonDecoder.decode(GeminiGenerateContentResponse.self, from: data)
                    let text = decoded.candidates?.first?.content?.parts?.compactMap(\.text).joined(separator: "\n")
                    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        completion(.failure(TranslationError.invalidResponse))
                        return
                    }
                    completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
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

		    func translate(text: String, targetLanguage: String, modelOverride: LLMModel?, completion: @escaping (Result<String, Error>) -> Void) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return
        }
        
        isTranslating = true
        errorMessage = nil

        let modelToUse = modelOverride ?? builtInTranslateModel
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
    func translateText(text: String, targetLanguage: String, modelOverride: LLMModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let modelToUse = modelOverride ?? builtInTranslateModel
        switch modelToUse.provider {
        case .openAI:
            let requestBody = buildRequestBody(text: text, targetLanguage: targetLanguage, modelName: modelToUse.name)
            return performOpenAIChatCompletion(apiKey: apiKey, requestBody: requestBody, completion: completion)
        case .gemini:
            return performGeminiGenerateContent(
                apiKey: geminiAPIKey,
                modelName: modelToUse.name,
                systemPrompt: translateSystemPrompt(targetLanguage: targetLanguage),
                userText: text,
                maxOutputTokens: 1000,
                temperature: 0.3,
                completion: completion
            )
        }
    }

    @discardableResult
    func translateHTML(html: String, targetLanguage: String, modelOverride: LLMModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let modelToUse = modelOverride ?? builtInTranslateModel
        switch modelToUse.provider {
        case .openAI:
            let requestBody = buildHTMLTranslateRequestBody(html: html, targetLanguage: targetLanguage, modelName: modelToUse.name)
            return performOpenAIChatCompletion(apiKey: apiKey, requestBody: requestBody, completion: completion)
        case .gemini:
            return performGeminiGenerateContent(
                apiKey: geminiAPIKey,
                modelName: modelToUse.name,
                systemPrompt: translateHTMLSystemPrompt(targetLanguage: targetLanguage),
                userText: html,
                maxOutputTokens: 1500,
                temperature: 0.2,
                completion: completion
            )
        }
    }

    @discardableResult
    func grammarFix(text: String, modelOverride: LLMModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let modelToUse = modelOverride ?? builtInTranslateModel
        switch modelToUse.provider {
        case .openAI:
            let requestBody = buildGrammarFixRequestBody(text: text, modelName: modelToUse.name)
            return performOpenAIChatCompletion(apiKey: apiKey, requestBody: requestBody, completion: completion)
        case .gemini:
            return performGeminiGenerateContent(
                apiKey: geminiAPIKey,
                modelName: modelToUse.name,
                systemPrompt: grammarSystemPrompt(),
                userText: text,
                maxOutputTokens: 1000,
                temperature: 0.2,
                completion: completion
            )
        }
    }

    @discardableResult
		    func runCustomAction(text: String, prompt: String, modelOverride: LLMModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
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

        let modelToUse = modelOverride ?? builtInTranslateModel
        switch modelToUse.provider {
        case .openAI:
            let requestBody = buildCustomActionRequestBody(text: trimmedText, prompt: trimmedPrompt, modelName: modelToUse.name)
            return performOpenAIChatCompletion(apiKey: apiKey, requestBody: requestBody) { [weak self] result in
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
        case .gemini:
            return performGeminiGenerateContent(
                apiKey: geminiAPIKey,
                modelName: modelToUse.name,
                systemPrompt: trimmedPrompt,
                userText: trimmedText,
                maxOutputTokens: 1500,
                temperature: 0.2,
                completion: { [weak self] result in
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
            )
        }
		    }

	    private func isCancellationError(_ error: Error) -> Bool {
	        let nsError = error as NSError
	        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
	    }

    @discardableResult
    func grammarFixHTML(html: String, modelOverride: LLMModel?, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(TranslationError.emptyText))
            return nil
        }

        let modelToUse = modelOverride ?? builtInTranslateModel
        switch modelToUse.provider {
        case .openAI:
            let requestBody = buildHTMLGrammarFixRequestBody(html: html, modelName: modelToUse.name)
            return performOpenAIChatCompletion(apiKey: apiKey, requestBody: requestBody, completion: completion)
        case .gemini:
            return performGeminiGenerateContent(
                apiKey: geminiAPIKey,
                modelName: modelToUse.name,
                systemPrompt: grammarHTMLSystemPrompt(),
                userText: html,
                maxOutputTokens: 1500,
                temperature: 0.2,
                completion: completion
            )
        }
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
