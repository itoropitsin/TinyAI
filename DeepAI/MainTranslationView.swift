import SwiftUI
import AppKit

struct MainTranslationView: View {
    @EnvironmentObject var translationService: TranslationService
    @State private var sourceText: String = ""
    @State private var primaryOutputText: String = ""
    @State private var secondaryOutputText: String = ""
    @State private var selectedLanguage: String = "English"
    @State private var showSettings: Bool = false
    @State private var processingTask: DispatchWorkItem?
    @State private var isPrimaryLoading: Bool = false
    @State private var isSecondaryLoading: Bool = false
    @State private var primaryRequestId: UUID = UUID()
    @State private var secondaryRequestId: UUID = UUID()
    @State private var primaryTitle: String = "Starred 1"
    @State private var secondaryTitle: String = "Starred 2"
    
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
                                primaryOutputText = ""
                                secondaryOutputText = ""
                                isPrimaryLoading = false
                                isSecondaryLoading = false
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
                VSplitView {
                    primarySection
                        .frame(minHeight: 0, maxHeight: .infinity)
                        .layoutPriority(1)
                    secondarySection
                        .frame(minHeight: 0, maxHeight: .infinity)
                        .layoutPriority(1)
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
        .onAppear {
            refreshTitles()
        }
        .onChange(of: selectedLanguage) { _ in
            guard translationService.isStarredPrimaryBuiltInTranslate else { return }
            refreshTitles()
            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                processText()
            }
        }
        .onChange(of: translationService.starredPrimarySelectionKey) { _ in
            refreshTitles()
            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                processText()
            }
        }
        .onChange(of: translationService.starredSecondaryActionId) { _ in
            refreshTitles()
            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                processText()
            }
        }
        .onChange(of: translationService.builtInTranslateModel) { _ in
            guard translationService.isStarredPrimaryBuiltInTranslate else { return }
            refreshTitles()
            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                processText()
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

    private func runBuiltInTranslate(target: OutputTarget, text: String) {
        guard target == .primary else {
            return
        }

        primaryTitle = "Translate"
        let requestId = UUID()
        primaryRequestId = requestId
        isPrimaryLoading = true

        translationService.translateText(text: text, targetLanguage: selectedLanguage, modelOverride: translationService.builtInTranslateModel) { result in
            guard primaryRequestId == requestId else { return }
            isPrimaryLoading = false
            switch result {
            case .success(let text):
                primaryOutputText = text
            case .failure(let error):
                primaryOutputText = ""
                translationService.errorMessage = error.localizedDescription
            }
        }
    }

    private var primarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(primaryTitle)
                    .font(.headline)
                Spacer()

                if translationService.isStarredPrimaryBuiltInTranslate {
                    Picker("", selection: $selectedLanguage) {
                        ForEach(languages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                Button(action: { copyTextToClipboard(primaryOutputText) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Копировать")
                .disabled(primaryOutputText.isEmpty || isPrimaryLoading)

                Button("Заменить") {
                    replaceSourceText(with: primaryOutputText)
                }
                .disabled(primaryOutputText.isEmpty || isPrimaryLoading)
            }

            if isPrimaryLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Обрабатываю...")
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
                    Text(primaryOutputText.isEmpty ? "Результат появится здесь..." : primaryOutputText)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundColor(primaryOutputText.isEmpty ? .secondary : .primary)
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

    private var secondarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(secondaryTitle)
                    .font(.headline)
                Spacer()

                Button(action: { copyTextToClipboard(secondaryOutputText) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Копировать")
                .disabled(secondaryOutputText.isEmpty || isSecondaryLoading)

                Button("Заменить") {
                    replaceSourceText(with: secondaryOutputText)
                }
                .disabled(secondaryOutputText.isEmpty || isSecondaryLoading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(translationService.customActions.enumerated()), id: \.element.id) { index, action in
                        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Action \(index + 1)"
                        : action.title

                        Button(title) {
                            runSecondaryAction(at: index)
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSecondaryLoading
                        )
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                    }
                }
                .padding(.vertical, 2)
            }

            if isSecondaryLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Обрабатываю...")
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
                    Text(secondaryOutputText.isEmpty ? "Результат появится здесь..." : secondaryOutputText)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundColor(secondaryOutputText.isEmpty ? .secondary : .primary)
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
        primaryOutputText = ""
        secondaryOutputText = ""
        isPrimaryLoading = false
        isSecondaryLoading = false
    }

    private func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func replaceSourceText(with text: String) {
        sourceText = text
    }

    private func processText() {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            primaryOutputText = ""
            secondaryOutputText = ""
            isPrimaryLoading = false
            isSecondaryLoading = false
            return
        }

        let primaryAction = translationService.starredPrimaryCustomAction()
        let secondaryAction = translationService.customActions.first(where: { $0.id == translationService.starredSecondaryActionId })

        if translationService.isStarredPrimaryBuiltInTranslate {
            runBuiltInTranslate(target: .primary, text: trimmed)
        } else {
            runAction(primaryAction, target: .primary, text: trimmed)
        }
        runAction(secondaryAction, target: .secondary, text: trimmed)
    }

    private func refreshTitles() {
        if translationService.isStarredPrimaryBuiltInTranslate {
            primaryTitle = "Translate"
        } else {
            let primaryAction = translationService.starredPrimaryCustomAction()
            if let primaryAction {
                let title = primaryAction.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Action" : primaryAction.title
                primaryTitle = title
            } else {
                primaryTitle = "Starred 1"
            }
        }

        let secondaryAction = translationService.customActions.first(where: { $0.id == translationService.starredSecondaryActionId })
        if let secondaryAction {
            let title = secondaryAction.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Action" : secondaryAction.title
            secondaryTitle = title
        } else {
            secondaryTitle = "Starred 2"
        }
    }

    private enum OutputTarget {
        case primary
        case secondary
    }

    private func runAction(_ action: CustomAction?, target: OutputTarget, text: String) {
        guard let action else {
            switch target {
            case .primary:
                primaryTitle = "Starred 1"
                primaryOutputText = ""
                isPrimaryLoading = false
            case .secondary:
                secondaryTitle = "Starred 2"
                secondaryOutputText = ""
                isSecondaryLoading = false
            }
            return
        }

        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Action" : action.title
        let prompt = action.prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedPrompt = prompt.replacingOccurrences(of: "{{targetLanguage}}", with: selectedLanguage)
        let emptyPromptMessage = "Промпт и модель для этого действия задаются в настройках."

        switch target {
        case .primary:
            primaryTitle = title
            let requestId = UUID()
            primaryRequestId = requestId
            if resolvedPrompt.isEmpty {
                isPrimaryLoading = false
                primaryOutputText = emptyPromptMessage
                return
            }
            isPrimaryLoading = true
            translationService.runCustomAction(text: text, prompt: resolvedPrompt, modelOverride: action.model) { result in
                guard primaryRequestId == requestId else { return }
                isPrimaryLoading = false
                switch result {
                case .success(let text):
                    primaryOutputText = text
                case .failure(let error):
                    primaryOutputText = ""
                    translationService.errorMessage = error.localizedDescription
                }
            }
        case .secondary:
            secondaryTitle = title
            let requestId = UUID()
            secondaryRequestId = requestId
            if resolvedPrompt.isEmpty {
                isSecondaryLoading = false
                secondaryOutputText = emptyPromptMessage
                return
            }
            isSecondaryLoading = true
            translationService.runCustomAction(text: text, prompt: resolvedPrompt, modelOverride: action.model) { result in
                guard secondaryRequestId == requestId else { return }
                isSecondaryLoading = false
                switch result {
                case .success(let text):
                    secondaryOutputText = text
                case .failure(let error):
                    secondaryOutputText = ""
                    translationService.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func runSecondaryAction(at index: Int) {
        guard index >= 0 && index < translationService.customActions.count else {
            return
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let action = translationService.customActions[index]
        runAction(action, target: .secondary, text: trimmed)
    }
}

