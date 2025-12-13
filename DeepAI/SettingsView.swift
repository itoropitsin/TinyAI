import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var translationService: TranslationService
    @Environment(\.dismiss) var dismiss
    @State private var apiKey: String = ""
    @State private var selectedModel: OpenAIModel = .gpt5Mini
    
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
                        Text("Модель")
                            .font(.headline)

                        Picker("", selection: $selectedModel) {
                            ForEach(OpenAIModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
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
                    translationService.saveSelectedModel(selectedModel)
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
            selectedModel = translationService.selectedModel
        }
    }
}

