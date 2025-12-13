import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var translationService: TranslationService
    @Environment(\.dismiss) var dismiss
    @State private var apiKey: String = ""
    @State private var isTranslationEnabled: Bool = true
    @State private var isGrammarEnabled: Bool = true
    @State private var translationModel: OpenAIModel = .gpt5Mini
    @State private var grammarModel: OpenAIModel = .gpt5Mini
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Настройки")
                .font(.title2)
                .padding(.top)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI API Key")
                            .font(.headline)

                        SecureField("Введите ваш API ключ", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        Text("Ваш API ключ хранится локально и используется только для переводов.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Link("Получить API ключ", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Режимы")
                            .font(.headline)

                        Toggle("Перевод", isOn: $isTranslationEnabled)
                            .disabled(isTranslationEnabled && !isGrammarEnabled)

                        Toggle("Исправление грамматики", isOn: $isGrammarEnabled)
                            .disabled(isGrammarEnabled && !isTranslationEnabled)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Модели")
                            .font(.headline)

                        HStack {
                            Text("Перевод")
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $translationModel) {
                                ForEach(OpenAIModel.allCases) { model in
                                    Text(model.displayName).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            .disabled(!isTranslationEnabled)
                        }

                        HStack {
                            Text("Грамматика")
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $grammarModel) {
                                ForEach(OpenAIModel.allCases) { model in
                                    Text(model.displayName).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            .disabled(!isGrammarEnabled)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Сохранить") {
                    translationService.saveAPIKey(apiKey)
                    translationService.saveIsTranslationEnabled(isTranslationEnabled)
                    translationService.saveIsGrammarEnabled(isGrammarEnabled)
                    translationService.saveTranslationModel(translationModel)
                    translationService.saveGrammarModel(grammarModel)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 520, height: 360)
        .onAppear {
            apiKey = translationService.apiKey
            isTranslationEnabled = translationService.isTranslationEnabled
            isGrammarEnabled = translationService.isGrammarEnabled
            translationModel = translationService.translationModel
            grammarModel = translationService.grammarModel
        }
    }
}

