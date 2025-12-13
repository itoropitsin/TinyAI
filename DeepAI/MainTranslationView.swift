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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Исходный текст")
                        .font(.headline)
                    Spacer()
                    Button(action: { clearSourceText() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Очистить")
                }
                
                TextEditor(text: $sourceText)
                    .font(.system(.body, design: .default))
                    .frame(minWidth: 200)
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
            .padding()
            .frame(minWidth: 300)
            
            // Правая панель - перевод
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Перевод")
                        .font(.headline)
                    Spacer()
                    
                    Picker("", selection: $selectedLanguage) {
                        ForEach(languages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    .onChange(of: selectedLanguage) { _ in
                        if !sourceText.isEmpty {
                            translate()
                        }
                    }
                    
                    Button(action: { copyTranslation() }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Копировать")
                    .disabled(translatedText.isEmpty)
                }
                
                if translationService.isTranslating {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Перевожу...")
                            .foregroundColor(.secondary)
                            .padding(.top)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(translatedText.isEmpty ? "Введите текст для перевода..." : translatedText)
                            .font(.system(.body, design: .default))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .foregroundColor(translatedText.isEmpty ? .secondary : .primary)
                    }
                }
            }
            .padding()
            .frame(minWidth: 300)
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

