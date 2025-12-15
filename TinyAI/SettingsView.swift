import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var translationService: TranslationService
    @EnvironmentObject var keyboardMonitor: KeyboardMonitor
    @Environment(\.dismiss) var dismiss
    @State private var apiKey: String = ""
    @State private var customActions: [CustomAction] = []
    @State private var starredPrimarySelectionKey: String = TranslationService.builtInTranslateSelectionKey
    @State private var starredSecondaryActionId: UUID?
    @State private var builtInTranslateModel: OpenAIModel = .gpt5Mini
    @State private var autoTranslateMainLanguage: String = "Russian"
    @State private var autoTranslateAdditionalLanguage: String = "English"
    @State private var popupHotkey: KeyboardShortcut = KeyboardShortcut(keyCode: 8, modifiers: [.command])
    @State private var popupHotkeyPressMode: PopupHotkeyPressMode = .doublePress
    @State private var popupHotkeyError: String?

    private let settingsLabelColumnWidth: CGFloat = 130
    private let settingsControlColumnWidth: CGFloat = 240
    private let customActionModelPickerWidth: CGFloat = 150
    private let autoTranslateLanguages = TranslationService.supportedLanguages
    
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
                        Text("Hotkeys")
                            .font(.headline)

                        HStack(alignment: .center, spacing: 12) {
                            Text("Popup")
                                .foregroundColor(.secondary)
                                .frame(width: settingsLabelColumnWidth, alignment: .leading)

                            KeyboardShortcutRecorder(
                                shortcut: popupHotkey,
                                isInvalid: popupHotkeyError != nil,
                                width: settingsControlColumnWidth
                            ) { candidate in
                                if let error = keyboardMonitor.validatePopupHotkey(candidate, pressMode: popupHotkeyPressMode) {
                                    popupHotkeyError = error
                                    return
                                }
                                popupHotkey = candidate
                                popupHotkeyError = nil
                            }
                        }
                        .padding(.vertical, 2)
                        .hoverRowHighlight()

                        HStack(alignment: .center, spacing: 12) {
                            Text("Trigger")
                                .foregroundColor(.secondary)
                                .frame(width: settingsLabelColumnWidth, alignment: .leading)

                            Picker("", selection: Binding(
                                get: { popupHotkeyPressMode },
                                set: { newMode in
                                    if let error = keyboardMonitor.validatePopupHotkey(popupHotkey, pressMode: newMode) {
                                        popupHotkeyError = error
                                        return
                                    }
                                    popupHotkeyPressMode = newMode
                                    popupHotkeyError = nil
                                }
                            )) {
                                ForEach(PopupHotkeyPressMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: settingsControlColumnWidth)
                        }
                        .padding(.vertical, 2)
                        .hoverRowHighlight()

                        HStack(alignment: .top, spacing: 12) {
                            Color.clear
                                .frame(width: settingsLabelColumnWidth, height: 1)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Note: ⌘1, ⌘2, ⌘3, … are static shortcuts and can’t be reassigned.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let popupHotkeyError {
                                    Text(popupHotkeyError)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .frame(width: settingsControlColumnWidth, alignment: .leading)
                        }
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

                            HStack(alignment: .center, spacing: 12) {
                                Text("Auto: Main")
                                    .foregroundColor(.secondary)
                                    .frame(width: settingsLabelColumnWidth, alignment: .leading)
                                Picker("", selection: $autoTranslateMainLanguage) {
                                    ForEach(autoTranslateLanguages, id: \.self) { language in
                                        Text(language).tag(language)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: settingsControlColumnWidth)
                            }
                            .padding(.vertical, 2)
                            .hoverRowHighlight()

                            HStack(alignment: .center, spacing: 12) {
                                Text("Auto: Add.")
                                    .foregroundColor(.secondary)
                                    .frame(width: settingsLabelColumnWidth, alignment: .leading)
                                Picker("", selection: $autoTranslateAdditionalLanguage) {
                                    ForEach(autoTranslateLanguages, id: \.self) { language in
                                        Text(language).tag(language)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: settingsControlColumnWidth)
                            }
                            .padding(.vertical, 2)
                            .hoverRowHighlight()

                            HStack(alignment: .top, spacing: 12) {
                                Color.clear
                                    .frame(width: settingsLabelColumnWidth, height: 1)
                                Text("Used only when the language menu is set to Auto.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: settingsControlColumnWidth, alignment: .leading)
                            }
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
                    translationService.saveAutoTranslateMainLanguage(autoTranslateMainLanguage)
                    translationService.saveAutoTranslateAdditionalLanguage(autoTranslateAdditionalLanguage)

                    if let error = keyboardMonitor.applyPopupHotkeySettings(shortcut: popupHotkey, pressMode: popupHotkeyPressMode) {
                        popupHotkeyError = error
                        return
                    }

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
            autoTranslateMainLanguage = translationService.autoTranslateMainLanguage
            autoTranslateAdditionalLanguage = translationService.autoTranslateAdditionalLanguage
            popupHotkey = keyboardMonitor.popupHotkey
            popupHotkeyPressMode = keyboardMonitor.popupHotkeyPressMode
            popupHotkeyError = nil
        }
    }
}

private struct KeyboardShortcutRecorder: View {
    let shortcut: KeyboardShortcut
    let isInvalid: Bool
    let width: CGFloat
    let onCaptured: (KeyboardShortcut) -> Void

    @State private var isRecording: Bool = false

    var body: some View {
        Button {
            isRecording = true
        } label: {
            HStack(spacing: 8) {
                Text(isRecording ? "Press shortcut…" : shortcut.displayString)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text("Change")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(width: width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isInvalid ? Color.red : Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .background(
            KeyCaptureViewRepresentable(isRecording: $isRecording) { keyCode, modifiers in
                let candidate = KeyboardShortcut(keyCode: Int64(keyCode), modifiers: modifiers)
                onCaptured(candidate)
            }
            .frame(width: 0, height: 0)
        )
    }
}

private struct KeyCaptureViewRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (UInt16, ShortcutModifiers) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCapture = { keyCode, modifiers in
            onCapture(keyCode, modifiers)
            DispatchQueue.main.async {
                isRecording = false
            }
        }
        view.onCancel = {
            DispatchQueue.main.async {
                isRecording = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class KeyCaptureView: NSView {
    var onCapture: ((UInt16, ShortcutModifiers) -> Void)?
    var onCancel: (() -> Void)?
    var isRecording: Bool = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // Escape
            onCancel?()
            return
        }

        let ignoredKeyCodes: Set<UInt16> = [
            54, 55, // ⌘
            56, 60, // ⇧
            58, 61, // ⌥
            59, 62  // ⌃
        ]
        if ignoredKeyCodes.contains(event.keyCode) {
            return
        }

        let modifiers = ShortcutModifiers(modifierFlags: event.modifierFlags)
        onCapture?(event.keyCode, modifiers)
    }
}
