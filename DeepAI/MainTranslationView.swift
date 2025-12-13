import SwiftUI
import AppKit

struct MainTranslationView: View {
    @EnvironmentObject var translationService: TranslationService
    @State private var sourceText: String = ""
    @State private var translatedText: String = ""
    @State private var grammarFixedText: String = ""
    @State private var selectedLanguage: String = "English"
    @State private var showSettings: Bool = false
    @State private var processingTask: DispatchWorkItem?
    @State private var isTranslationLoading: Bool = false
    @State private var isGrammarLoading: Bool = false
    @State private var currentRequestId: UUID = UUID()
    
    let languages = [
        "English", "Russian", "Spanish", "French", "German", "Italian",
        "Portuguese", "Chinese", "Japanese", "Korean", "Arabic", "Dutch",
        "Polish", "Turkish", "Swedish", "Norwegian", "Danish", "Finnish"
    ]
    
    var body: some View {
        HSplitView {
            // Левая панель - исходный текст
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Исходный текст")
                        .font(.headline)
                    Spacer()
                    Button(action: { clearSourceText() }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Очистить")
                    .disabled(sourceText.isEmpty)
                }
                
                ZStack(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("Введите текст для перевода...")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    
                    TextEditor(text: $sourceText)
                        .font(.system(.body, design: .default))
                        .frame(minWidth: 220)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .onChange(of: sourceText) { _ in
                            processingTask?.cancel()
                            
                            if sourceText.isEmpty {
                                translatedText = ""
                                grammarFixedText = ""
                                isTranslationLoading = false
                                isGrammarLoading = false
                            } else {
                                // Создаем новую задачу с задержкой для debounce
                                let task = DispatchWorkItem {
                                    processText()
                                }
                                processingTask = task
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
                            }
                        }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .padding(16)
            .frame(minWidth: 340)
            
            // Правая панель - результаты
            VStack(alignment: .leading, spacing: 12) {
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
            .frame(minWidth: 340)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .help("Настройки")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(translationService)
        }
        .alert("Ошибка", isPresented: Binding(
            get: { translationService.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    translationService.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                translationService.errorMessage = nil
            }
        } message: {
            Text(translationService.errorMessage ?? "")
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .frame(width: 170)
                .onChange(of: selectedLanguage) { _ in
                    if !sourceText.isEmpty {
                        processText(translationOnly: true)
                    }
                }

                Button(action: { copyTextToClipboard(translatedText) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Копировать")
                .disabled(translatedText.isEmpty || isTranslationLoading)

                Button("Заменить") {
                    replaceSourceText(with: translatedText)
                }
                .disabled(translatedText.isEmpty || isTranslationLoading)
            }

            if isTranslationLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Перевожу...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            } else {
                ScrollView {
                    Text(translatedText.isEmpty ? "Перевод появится здесь..." : translatedText)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundColor(translatedText.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var grammarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Исправление грамматики")
                    .font(.headline)
                Spacer()

                Button(action: { copyTextToClipboard(grammarFixedText) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Копировать")
                .disabled(grammarFixedText.isEmpty || isGrammarLoading)

                Button("Заменить") {
                    replaceSourceText(with: grammarFixedText)
                }
                .disabled(grammarFixedText.isEmpty || isGrammarLoading)
            }

            if isGrammarLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Исправляю...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            } else {
                ScrollView {
                    Text(grammarFixedText.isEmpty ? "Исправленная версия появится здесь..." : grammarFixedText)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundColor(grammarFixedText.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .layoutPriority(1)
    }
    
    private func clearSourceText() {
        sourceText = ""
        translatedText = ""
        grammarFixedText = ""
        isTranslationLoading = false
        isGrammarLoading = false
    }

    private func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func replaceSourceText(with text: String) {
        sourceText = text
    }

    private func processText(translationOnly: Bool = false) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                }
            }
        } else {
            grammarFixedText = ""
            isGrammarLoading = false
        }
    }
}

