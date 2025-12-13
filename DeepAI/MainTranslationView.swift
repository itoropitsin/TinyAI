import SwiftUI
import AppKit

struct MainTranslationView: View {
    @EnvironmentObject var translationService: TranslationService
    @State private var sourceText: String = ""
    @State private var translatedText: String = ""
    @State private var selectedLanguage: String = "English"
    @State private var showSettings: Bool = false
    @State private var translationTask: DispatchWorkItem?
    
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
                            // Отменяем предыдущую задачу перевода
                            translationTask?.cancel()
                            
                            if sourceText.isEmpty {
                                translatedText = ""
                            } else {
                                // Создаем новую задачу с задержкой для debounce
                                let task = DispatchWorkItem {
                                    translate()
                                }
                                translationTask = task
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
            
            // Правая панель - перевод
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
                            translate()
                        }
                    }
                    
                    Button(action: { copyTranslation() }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Копировать")
                    .disabled(translatedText.isEmpty || translationService.isTranslating)
                }
                
                if translationService.isTranslating {
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
    
    private func translate() {
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translatedText = ""
            return
        }
        
        translationService.translate(text: sourceText, targetLanguage: selectedLanguage) { result in
            switch result {
            case .success(let text):
                translatedText = text
            case .failure(let error):
                translatedText = ""
                translationService.errorMessage = error.localizedDescription
                print("Translation error: \(error.localizedDescription)")
            }
        }
    }
    
    private func clearSourceText() {
        sourceText = ""
        translatedText = ""
    }
    
    private func copyTranslation() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
    }
}

