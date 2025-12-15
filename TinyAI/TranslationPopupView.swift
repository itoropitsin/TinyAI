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
    @State private var isLanguageMenuOpen: Bool = false
    @State private var languageButtonFrame: CGRect = .zero
    
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

    private struct FramePreferenceKey: PreferenceKey {
        static var defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            value = nextValue()
        }
    }

    private struct PopupLanguagePickerButton: View {
        @Binding var selectedLanguage: String
        @Binding var isOpen: Bool
        @Binding var buttonFrame: CGRect

        private let menuWidth: CGFloat = 160
        private let controlHeight: CGFloat = 28

        var body: some View {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(selectedLanguage)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(width: menuWidth, height: controlHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: FramePreferenceKey.self, value: proxy.frame(in: .named("PopupRoot")))
                }
            )
            .onPreferenceChange(FramePreferenceKey.self) { newValue in
                buttonFrame = newValue
            }
        }
    }

    private struct PopupLanguageMenu: View {
        @Binding var selectedLanguage: String
        let languages: [String]
        let onSelect: () -> Void
        private let menuWidth: CGFloat = 160
        @State private var hoveredLanguage: String?

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(languages, id: \.self) { language in
                        Button {
                            selectedLanguage = language
                            onSelect()
                        } label: {
                            Text(language)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(language == selectedLanguage
                            ? Color(NSColor.selectedContentBackgroundColor).opacity(0.22)
                            : (hoveredLanguage == language
                                ? Color(NSColor.unemphasizedSelectedContentBackgroundColor).opacity(0.18)
                                : Color.clear))
                        .onHover { isHovering in
                            hoveredLanguage = isHovering ? language : (hoveredLanguage == language ? nil : hoveredLanguage)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: menuWidth, height: 220)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .shadow(radius: 10, y: 6)
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 12) {
                // Header - make it draggable
                HStack(spacing: 10) {
                    Text("TinyAI")
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

            if isLanguageMenuOpen {
                GeometryReader { _ in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isLanguageMenuOpen = false
                            }

                        PopupLanguageMenu(
                            selectedLanguage: $selectedLanguage,
                            languages: languages,
                            onSelect: { isLanguageMenuOpen = false }
                        )
                        .offset(x: languageButtonFrame.minX, y: languageButtonFrame.maxY + 6)
                    }
                }
                .zIndex(1000)
            }
        }
        .coordinateSpace(name: "PopupRoot")
        .frame(minWidth: 420, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
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
        .onChange(of: selectedLanguage) { _, _ in
            isLanguageMenuOpen = false
            guard translationService.isStarredPrimaryBuiltInTranslate else { return }
            refreshTitles()
            processText()
        }
        .onChange(of: translationService.starredPrimarySelectionKey) { _, _ in
            isLanguageMenuOpen = false
            refreshTitles()
            processText()
        }
        .onChange(of: translationService.starredSecondaryActionId) { _, _ in
            isLanguageMenuOpen = false
            refreshTitles()
            processText()
        }
        .onChange(of: translationService.builtInTranslateModel) { _, _ in
            isLanguageMenuOpen = false
            guard translationService.isStarredPrimaryBuiltInTranslate else { return }
            refreshTitles()
            processText()
        }
        .onReceive(translationService.$customActions) { _ in
            refreshTitles()
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
                let fallbackTitle = translationService.customActions
                    .firstIndex(where: { $0.id == primaryAction.id })
                    .map { "Action \($0 + 1)" } ?? "Action 1"
                let title = primaryAction.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : primaryAction.title
                primaryTitle = title
            } else {
                primaryTitle = "Starred 1"
            }
        }

        let secondaryAction = translationService.customActions.first(where: { $0.id == translationService.starredSecondaryActionId })
        if let secondaryAction {
            let fallbackTitle = translationService.customActions
                .firstIndex(where: { $0.id == secondaryAction.id })
                .map { "Action \($0 + 1)" } ?? "Action 2"
            let title = secondaryAction.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : secondaryAction.title
            secondaryTitle = title
        } else {
            secondaryTitle = "Starred 2"
        }
    }

    private func outputView(text: String, isLoading: Bool, emptyText: String) -> some View {
        ZStack {
            ScrollView {
                Text(text.isEmpty ? emptyText : text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .foregroundColor(text.isEmpty ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }


    private var primarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(primaryTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()

                if translationService.isStarredPrimaryBuiltInTranslate {
                    PopupLanguagePickerButton(
                        selectedLanguage: $selectedLanguage,
                        isOpen: $isLanguageMenuOpen,
                        buttonFrame: $languageButtonFrame
                    )
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

            outputView(text: primaryOutputText, isLoading: isPrimaryLoading, emptyText: "Result will appear here...")
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var secondarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            outputView(text: secondaryOutputText, isLoading: isSecondaryLoading, emptyText: "Result will appear here...")
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

        let fallbackTitle: String = {
            let index = translationService.customActions.firstIndex(where: { $0.id == action.id })
            let defaultIndex = (target == .primary) ? 0 : 1
            return "Action \((index ?? defaultIndex) + 1)"
        }()
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : action.title
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
