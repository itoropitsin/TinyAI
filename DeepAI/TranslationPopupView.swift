import SwiftUI
import AppKit

struct TranslationPopupView: View {
    let selectedText: String
    let onClose: (() -> Void)?
    @EnvironmentObject var translationService: TranslationService
    @State private var translatedText: String = ""
    @State private var grammarFixedText: String = ""
    @State private var selectedLanguage: String = "English"
    @State private var showError: Bool = false
    @State private var isTranslationLoading: Bool = false
    @State private var isGrammarLoading: Bool = false
    @State private var currentRequestId: UUID = UUID()
    
    init(selectedText: String, onClose: (() -> Void)? = nil) {
        self.selectedText = selectedText
        self.onClose = onClose
    }
    
    let languages = [
        "English", "Russian", "Spanish", "French", "German", "Italian",
        "Portuguese", "Chinese", "Japanese", "Korean", "Arabic", "Dutch",
        "Polish", "Turkish", "Swedish", "Norwegian", "Danish", "Finnish"
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // Заголовок - делаем его перетаскиваемым
            HStack(spacing: 10) {
                Text("DeepAI")
                    .font(.headline)
                Spacer()
                Button(action: {
                    onClose?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if translationService.isTranslationEnabled && translationService.isGrammarEnabled {
                VSplitView {
                    translationSection
                        .frame(minHeight: 0, maxHeight: .infinity)
                        .layoutPriority(1)
                    grammarSection
                        .frame(minHeight: 0, maxHeight: .infinity)
                        .layoutPriority(1)
                }
            } else if translationService.isTranslationEnabled {
                translationSection
            } else if translationService.isGrammarEnabled {
                grammarSection
            }
        }
        .padding(16)
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(14)
        .shadow(radius: 12)
        .onAppear {
            processText()
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(translationService.errorMessage ?? "Произошла ошибка при переводе")
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Перевод")
                    .font(.headline)
                Spacer()

                Picker("", selection: $selectedLanguage) {
                    ForEach(languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: selectedLanguage) { _ in
                    processText(translationOnly: true)
                }

                Button(action: { copyToClipboard(translatedText) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Копировать")
                .disabled(translatedText.isEmpty || isTranslationLoading)

                Button("Заменить") {
                    replaceText(with: translatedText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(translatedText.isEmpty || isTranslationLoading)
            }

            if isTranslationLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    Text(translatedText.isEmpty ? "Перевод появится здесь..." : translatedText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundColor(translatedText.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var grammarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Грамматика")
                    .font(.headline)
                Spacer()

                Button(action: { copyToClipboard(grammarFixedText) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Копировать")
                .disabled(grammarFixedText.isEmpty || isGrammarLoading)

                Button("Заменить") {
                    replaceText(with: grammarFixedText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(grammarFixedText.isEmpty || isGrammarLoading)
            }

            if isGrammarLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    Text(grammarFixedText.isEmpty ? "Исправленная версия появится здесь..." : grammarFixedText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundColor(grammarFixedText.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .layoutPriority(1)
    }
    
    private func processText(translationOnly: Bool = false) {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translatedText = ""
            grammarFixedText = ""
            isTranslationLoading = false
            isGrammarLoading = false
            return
        }

        let requestId = UUID()
        currentRequestId = requestId

        if translationService.isTranslationEnabled {
            isTranslationLoading = true
            translationService.translateText(text: trimmed, targetLanguage: selectedLanguage, modelOverride: nil) { result in
                guard currentRequestId == requestId else { return }
                isTranslationLoading = false
                switch result {
                case .success(let text):
                    translatedText = text
                case .failure(let error):
                    translatedText = ""
                    translationService.errorMessage = error.localizedDescription
                    showError = true
                }
            }
        } else {
            translatedText = ""
            isTranslationLoading = false
        }

        if translationOnly {
            return
        }

        if translationService.isGrammarEnabled {
            isGrammarLoading = true
            translationService.grammarFix(text: trimmed, modelOverride: nil) { result in
                guard currentRequestId == requestId else { return }
                isGrammarLoading = false
                switch result {
                case .success(let text):
                    grammarFixedText = text
                case .failure(let error):
                    grammarFixedText = ""
                    translationService.errorMessage = error.localizedDescription
                    showError = true
                }
            }
        } else {
            grammarFixedText = ""
            isGrammarLoading = false
        }
    }

    private func replaceText(with text: String) {
        // Копируем текст в буфер обмена
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Небольшая задержка перед вставкой
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Вставляем текст (Command-V)
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }

        onClose?()
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

