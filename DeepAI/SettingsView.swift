import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var translationService: TranslationService
    @Environment(\.dismiss) var dismiss
    @State private var apiKey: String = ""
    @State private var customActions: [CustomAction] = []
    @State private var starredPrimarySelectionKey: String = TranslationService.builtInTranslateSelectionKey
    @State private var starredSecondaryActionId: UUID?
    @State private var builtInTranslateModel: OpenAIModel = .gpt5Mini

    private let settingsLabelColumnWidth: CGFloat = 130
    private let settingsControlColumnWidth: CGFloat = 240
    private let customActionModelPickerWidth: CGFloat = 150
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .padding(.top)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI API Key")
                            .font(.headline)

                        SecureField("Enter your API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        Text("Your API key is stored locally and used only for translations.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Link("Get an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Primary actions")
                            .font(.headline)

                        HStack(alignment: .center, spacing: 12) {
                            Text("Starred 1")
                                .foregroundColor(.secondary)
                                .frame(width: settingsLabelColumnWidth, alignment: .leading)
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
                            .frame(width: settingsControlColumnWidth)
                        }
                        .padding(.vertical, 2)
                        .hoverRowHighlight()

                        if starredPrimarySelectionKey == TranslationService.builtInTranslateSelectionKey {
                            HStack(alignment: .center, spacing: 12) {
                                Text("Translate model")
                                    .foregroundColor(.secondary)
                                    .frame(width: settingsLabelColumnWidth, alignment: .leading)
                                Picker("", selection: $builtInTranslateModel) {
                                    ForEach(OpenAIModel.allCases) { model in
                                        Text(model.displayName).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: settingsControlColumnWidth)
                            }
                            .padding(.vertical, 2)
                            .hoverRowHighlight()
                        }

                        HStack(alignment: .center, spacing: 12) {
                            Text("Starred 2")
                                .foregroundColor(.secondary)
                                .frame(width: settingsLabelColumnWidth, alignment: .leading)
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
                            .frame(width: settingsControlColumnWidth)
                        }
                        .padding(.vertical, 2)
                        .hoverRowHighlight()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom actions")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(customActions.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Button \(index + 1)")
                                        .foregroundColor(.secondary)

                                    HStack(alignment: .center, spacing: 12) {
                                        TextField(
                                            "Title",
                                            text: Binding(
                                                get: { customActions[index].title },
                                                set: { customActions[index].title = String($0.prefix(25)) }
                                            )
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .frame(minWidth: 220)

                                        Picker("", selection: $customActions[index].model) {
                                            ForEach(OpenAIModel.allCases) { model in
                                                Text(model.displayName).tag(model)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(width: customActionModelPickerWidth)
                                    }

                                    TextEditor(text: $customActions[index].prompt)
                                        .frame(height: 90)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                        )
                                }
                                .hoverRowHighlight()
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .hoverHighlight()
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    translationService.saveAPIKey(apiKey)
                    let normalizedActions = customActions.map { action in
                        var copy = action
                        copy.title = String(copy.title.prefix(25))
                        return copy
                    }
                    customActions = normalizedActions
                    translationService.saveCustomActions(normalizedActions)
                    translationService.saveStarredPrimarySelectionKey(starredPrimarySelectionKey)
                    translationService.saveBuiltInTranslateModel(builtInTranslateModel)
                    translationService.saveStarredSecondaryActionId(starredSecondaryActionId)
                    dismiss()
                }
                .hoverHighlight()
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 520, height: 720)
        .onAppear {
            apiKey = translationService.apiKey
            customActions = translationService.customActions.map { action in
                var copy = action
                copy.title = String(copy.title.prefix(25))
                return copy
            }
            starredPrimarySelectionKey = translationService.starredPrimarySelectionKey
            starredSecondaryActionId = translationService.starredSecondaryActionId
            builtInTranslateModel = translationService.builtInTranslateModel
        }
    }
}

