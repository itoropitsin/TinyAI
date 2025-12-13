import SwiftUI
import AppKit

struct TranslationPopupView: View {
    let selectedText: String
    let onClose: (() -> Void)?
    @EnvironmentObject var translationService: TranslationService
    @State private var translatedText: String = ""
    @State private var selectedLanguage: String = "English"
    @State private var showError: Bool = false
    
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
                Text("Перевод")
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
            
            // Выбор языка
            HStack {
                Text("Язык перевода")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $selectedLanguage) {
                    ForEach(languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220)
                .onChange(of: selectedLanguage) { _ in
                    translate()
                }
            }
            
            // Исходный текст
            EmptyView()
            
            // Переведенный текст
            VStack(alignment: .leading, spacing: 6) {
                Text("Перевод")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if translationService.isTranslating {
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
            
            // Кнопки
            HStack(spacing: 10) {
                Spacer()
                Button("Копировать") {
                    copyToClipboard()
                }
                .buttonStyle(.bordered)
                .disabled(translatedText.isEmpty || translationService.isTranslating)
                
                Button("Заменить") {
                    replaceText()
                }
                .buttonStyle(.borderedProminent)
                .disabled(translatedText.isEmpty || translationService.isTranslating)
            }
        }
        .padding(16)
        .frame(width: 400, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(14)
        .shadow(radius: 12)
        .onAppear {
            translate()
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(translationService.errorMessage ?? "Произошла ошибка при переводе")
        }
    }
    
    private func translate() {
        translationService.translate(text: selectedText, targetLanguage: selectedLanguage) { result in
            switch result {
            case .success(let text):
                translatedText = text
            case .failure(let error):
                showError = true
                print("Translation error: \(error.localizedDescription)")
            }
        }
    }
    
    private func replaceText() {
        // Копируем переведенный текст в буфер обмена
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
        
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
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
    }
}

