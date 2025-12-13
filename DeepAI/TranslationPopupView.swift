import SwiftUI
import AppKit
import Combine

struct TranslationPopupView: View {
    let selectedText: String
    let selectedPayload: RichTextPayload?
    let onClose: (() -> Void)?
    @EnvironmentObject var translationService: TranslationService
    @EnvironmentObject var keyboardMonitor: KeyboardMonitor
    @State private var primaryOutputText: String = ""
    @State private var secondaryOutputText: String = ""
    @State private var primaryOutputPayload: RichTextPayload?
    @State private var secondaryOutputPayload: RichTextPayload?
    @State private var selectedLanguage: String = "English"
    @State private var showError: Bool = false
    @State private var isPrimaryLoading: Bool = false
    @State private var isSecondaryLoading: Bool = false
    @State private var primaryRequestId: UUID = UUID()
    @State private var secondaryRequestId: UUID = UUID()
    @State private var primaryNetworkTask: URLSessionDataTask?
    @State private var secondaryNetworkTask: URLSessionDataTask?
    @State private var primaryTitle: String = "Starred 1"
    @State private var secondaryTitle: String = "Starred 2"
    
    init(selectedText: String, selectedPayload: RichTextPayload? = nil, onClose: (() -> Void)? = nil) {
        self.selectedText = selectedText
        self.selectedPayload = selectedPayload
        self.onClose = onClose
    }
    
    let languages = [
        "English", "Russian", "Spanish", "French", "German", "Italian",
        "Portuguese", "Chinese", "Japanese", "Korean", "Arabic", "Dutch",
        "Polish", "Turkish", "Swedish", "Norwegian", "Danish", "Finnish"
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // Header - make it draggable
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
                .hoverHighlight()
            }

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
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(14)
        .shadow(radius: 12)
        .onAppear {
            keyboardMonitor.isCustomActionHotkeysEnabled = true
            refreshTitles()
            processText()
        }
        .onDisappear {
            keyboardMonitor.isCustomActionHotkeysEnabled = false
            primaryNetworkTask?.cancel()
            secondaryNetworkTask?.cancel()
        }
        .onReceive(keyboardMonitor.$customActionHotkey) { hotkey in
            guard let hotkey else { return }
            runSecondaryAction(at: hotkey - 1)
        }
        .onChange(of: selectedLanguage) { _ in
            guard translationService.isStarredPrimaryBuiltInTranslate else { return }
            refreshTitles()
            processText()
        }
        .onChange(of: translationService.starredPrimarySelectionKey) { _ in
            refreshTitles()
            processText()
        }
        .onChange(of: translationService.starredSecondaryActionId) { _ in
            refreshTitles()
            processText()
        }
        .onChange(of: translationService.builtInTranslateModel) { _ in
            guard translationService.isStarredPrimaryBuiltInTranslate else { return }
            refreshTitles()
            processText()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(translationService.errorMessage ?? "An error occurred during translation")
        }
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


    private var primarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    .labelsHidden()
                    .frame(width: 160)
                }

                Button(action: {
                    copyToClipboard(primaryOutputPayload ?? RichTextPayload(plain: primaryOutputText, html: nil, rtf: nil))
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .hoverHighlight()
                .help("Copy")
                .disabled(primaryOutputText.isEmpty || isPrimaryLoading)

                Button("Replace") {
                    replaceText(with: primaryOutputPayload ?? RichTextPayload(plain: primaryOutputText, html: nil, rtf: nil))
                }
                .buttonStyle(.borderedProminent)
                .hoverHighlight()
                .disabled(primaryOutputText.isEmpty || isPrimaryLoading)
            }

            if isPrimaryLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    Text(primaryOutputText.isEmpty ? "Result will appear here..." : primaryOutputText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundColor(primaryOutputText.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var secondarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(secondaryTitle)
                    .font(.headline)
                Spacer()

                Button(action: {
                    copyToClipboard(secondaryOutputPayload ?? RichTextPayload(plain: secondaryOutputText, html: nil, rtf: nil))
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .hoverHighlight()
                .help("Copy")
                .disabled(secondaryOutputText.isEmpty || isSecondaryLoading)

                Button("Replace") {
                    replaceText(with: secondaryOutputPayload ?? RichTextPayload(plain: secondaryOutputText, html: nil, rtf: nil))
                }
                .buttonStyle(.borderedProminent)
                .hoverHighlight()
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
                        .hoverHighlight()
                        .disabled(
                            selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSecondaryLoading
                        )
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                    }
                }
                .padding(.vertical, 2)
            }

            if isSecondaryLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    Text(secondaryOutputText.isEmpty ? "Result will appear here..." : secondaryOutputText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundColor(secondaryOutputText.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private func processText() {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            primaryNetworkTask?.cancel()
            secondaryNetworkTask?.cancel()
            primaryOutputText = ""
            secondaryOutputText = ""
            primaryOutputPayload = nil
            secondaryOutputPayload = nil
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
                primaryOutputPayload = nil
                isPrimaryLoading = false
            case .secondary:
                secondaryTitle = "Starred 2"
                secondaryOutputText = ""
                secondaryOutputPayload = nil
                isSecondaryLoading = false
            }
            return
        }

        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Action" : action.title
        let prompt = action.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPrompt = prompt.replacingOccurrences(of: "{{targetLanguage}}", with: selectedLanguage)
        let emptyPromptMessage = "Configure the prompt and model for this action in Settings."

        switch target {
        case .primary:
            primaryTitle = title
            let requestId = UUID()
            primaryRequestId = requestId
            if resolvedPrompt.isEmpty {
                isPrimaryLoading = false
                primaryOutputText = emptyPromptMessage
                primaryOutputPayload = RichTextPayload(plain: emptyPromptMessage, html: nil, rtf: nil)
                return
            }
            isPrimaryLoading = true
            primaryNetworkTask?.cancel()
            primaryNetworkTask = translationService.runCustomAction(text: text, prompt: resolvedPrompt, modelOverride: action.model) { result in
                guard primaryRequestId == requestId else { return }
                isPrimaryLoading = false
                switch result {
                case .success(let text):
                    primaryOutputText = text
                    primaryOutputPayload = RichTextPayload(plain: text, html: nil, rtf: nil)
                case .failure(let error):
                    if (error as? URLError)?.code == .cancelled { return }
                    primaryOutputText = ""
                    primaryOutputPayload = nil
                    translationService.errorMessage = error.localizedDescription
                    showError = true
                }
            }
        case .secondary:
            secondaryTitle = title
            let requestId = UUID()
            secondaryRequestId = requestId
            if resolvedPrompt.isEmpty {
                isSecondaryLoading = false
                secondaryOutputText = emptyPromptMessage
                secondaryOutputPayload = RichTextPayload(plain: emptyPromptMessage, html: nil, rtf: nil)
                return
            }
            isSecondaryLoading = true
            secondaryNetworkTask?.cancel()
            secondaryNetworkTask = translationService.runCustomAction(text: text, prompt: resolvedPrompt, modelOverride: action.model) { result in
                guard secondaryRequestId == requestId else { return }
                isSecondaryLoading = false
                switch result {
                case .success(let text):
                    secondaryOutputText = text
                    secondaryOutputPayload = RichTextPayload(plain: text, html: nil, rtf: nil)
                case .failure(let error):
                    if (error as? URLError)?.code == .cancelled { return }
                    secondaryOutputText = ""
                    secondaryOutputPayload = nil
                    translationService.errorMessage = error.localizedDescription
                    showError = true
                }
            }
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
        primaryNetworkTask?.cancel()

        primaryNetworkTask = translationService.translateText(text: text, targetLanguage: selectedLanguage, modelOverride: translationService.builtInTranslateModel) { result in
            guard primaryRequestId == requestId else { return }
            isPrimaryLoading = false
            switch result {
            case .success(let text):
                primaryOutputText = text
                primaryOutputPayload = RichTextPayload(plain: text, html: nil, rtf: nil)
            case .failure(let error):
                if (error as? URLError)?.code == .cancelled { return }
                primaryOutputText = ""
                primaryOutputPayload = nil
                translationService.errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func runSecondaryAction(at index: Int) {
        guard index >= 0 && index < translationService.customActions.count else {
            return
        }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let action = translationService.customActions[index]
        runAction(action, target: .secondary, text: trimmed)
    }

    private func replaceText(with payload: RichTextPayload) {
        let pasteboard = NSPasteboard.general
        RichTextPasteboard.write(payload, to: pasteboard)

        // Small delay before paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Paste text (Command-V)
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }

        onClose?()
    }

    private func copyToClipboard(_ payload: RichTextPayload) {
        let pasteboard = NSPasteboard.general
        RichTextPasteboard.write(payload, to: pasteboard)
    }
}
