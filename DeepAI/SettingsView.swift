import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var translationService: TranslationService
    @Environment(\.dismiss) var dismiss
    @State private var apiKey: String = ""
    @State private var customActions: [CustomAction] = []
    @State private var starredPrimarySelectionKey: String = TranslationService.builtInTranslateSelectionKey
    @State private var starredSecondaryActionId: UUID?
    @State private var builtInTranslateModel: OpenAIModel = .gpt5Mini
    
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
                        Text("Основные действия")
                            .font(.headline)

                        HStack {
                            Text("Starred 1")
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { starredPrimarySelectionKey },
                                set: { starredPrimarySelectionKey = $0 }
                            )) {
                                Text("Translate").tag(TranslationService.builtInTranslateSelectionKey)
                                ForEach(customActions) { action in
                                    let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Action"
                                    : action.title
                                    Text(title).tag(action.id.uuidString)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 240)
                        }

                        if starredPrimarySelectionKey == TranslationService.builtInTranslateSelectionKey {
                            HStack {
                                Text("Translate model")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Picker("", selection: $builtInTranslateModel) {
                                    ForEach(OpenAIModel.allCases) { model in
                                        Text(model.displayName).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 240)
                            }
                        }

                        HStack {
                            Text("Starred 2")
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { starredSecondaryActionId ?? customActions.first?.id },
                                set: { starredSecondaryActionId = $0 }
                            )) {
                                ForEach(customActions) { action in
                                    let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Action"
                                    : action.title
                                    Text(title).tag(Optional(action.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 240)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Кастомные действия")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(customActions.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Кнопка \(index + 1)")
                                        .foregroundColor(.secondary)

                                    TextField("Title", text: $customActions[index].title)
                                        .textFieldStyle(.roundedBorder)

                                    Picker("", selection: $customActions[index].model) {
                                        ForEach(OpenAIModel.allCases) { model in
                                            Text(model.displayName).tag(model)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 240)

                                    TextEditor(text: $customActions[index].prompt)
                                        .frame(height: 90)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                        )
                                }
                            }
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
                    translationService.saveCustomActions(customActions)
                    translationService.saveStarredPrimarySelectionKey(starredPrimarySelectionKey)
                    translationService.saveBuiltInTranslateModel(builtInTranslateModel)
                    translationService.saveStarredSecondaryActionId(starredSecondaryActionId)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 520, height: 720)
        .onAppear {
            apiKey = translationService.apiKey
            customActions = translationService.customActions
            starredPrimarySelectionKey = translationService.starredPrimarySelectionKey
            starredSecondaryActionId = translationService.starredSecondaryActionId
            builtInTranslateModel = translationService.builtInTranslateModel
        }
    }
}

