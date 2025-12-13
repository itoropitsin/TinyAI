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
        VStack(spacing: 16) {
            // Заголовок - делаем его перетаскиваемым
            HStack {
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
            .padding(.horizontal)
            .padding(.top)
            
            // Выбор языка
            Picker("Язык перевода", selection: $selectedLanguage) {
                ForEach(languages, id: \.self) { language in
                    Text(language).tag(language)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
            .onChange(of: selectedLanguage) { _ in
                translate()
            }
            
            // Исходный текст
            VStack(alignment: .leading, spacing: 4) {
                Text("Исходный текст:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(selectedText)
                    .font(.body)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }
            .padding(.horizontal)
            
            // Переведенный текст
            VStack(alignment: .leading, spacing: 4) {
                Text("Перевод:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if translationService.isTranslating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text(translatedText.isEmpty ? "Перевод появится здесь..." : translatedText)
                        .font(.body)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .foregroundColor(translatedText.isEmpty ? .secondary : .primary)
                }
            }
            .padding(.horizontal)
            
            // Кнопки
            HStack(spacing: 12) {
                Button("Заменить") {
                    replaceText()
                }
                .buttonStyle(.borderedProminent)
                .disabled(translatedText.isEmpty || translationService.isTranslating)
                
                Button("Копировать") {
                    copyToClipboard()
                }
                .buttonStyle(.bordered)
                .disabled(translatedText.isEmpty || translationService.isTranslating)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 400, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
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

