import SwiftUI
import AppKit

struct MainTranslationView: View {
    @EnvironmentObject var translationService: TranslationService
    @State private var sourceText: String = ""
    @State private var primaryOutputText: String = ""
    @State private var secondaryOutputText: String = ""
    @State private var showSettings: Bool = false
    @State private var showHelp: Bool = false
    @State private var processingTask: DispatchWorkItem?
    @State private var isPrimaryLoading: Bool = false
    @State private var isSecondaryLoading: Bool = false
    @State private var primaryRequestId: UUID = UUID()
    @State private var secondaryRequestId: UUID = UUID()
    @State private var primaryNetworkTask: URLSessionDataTask?
    @State private var secondaryNetworkTask: URLSessionDataTask?
	    @State private var primaryTitle: String = "Starred 1"
	    @State private var secondaryTitle: String = "Starred 2"
    
    let languages = [TranslationService.languageAutoSelection] + TranslationService.supportedLanguages
    
    var body: some View {
        HSplitView {
            // Left panel - source text
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Source text")
                        .font(.headline)
                    Spacer()
                    Button(action: { clearSourceText() }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .hoverHighlight()
                    .help("Clear")
                    .disabled(sourceText.isEmpty)
                }
                
                ZStack(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("Enter text to translate...")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    
                    TextEditor(text: $sourceText)
                        .font(.system(.body, design: .default))
                        .frame(minWidth: 220)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .onChange(of: sourceText) { _, _ in
                            processingTask?.cancel()
                            
                            if sourceText.isEmpty {
                                primaryNetworkTask?.cancel()
                                secondaryNetworkTask?.cancel()
                                primaryOutputText = ""
                                secondaryOutputText = ""
                                isPrimaryLoading = false
                                isSecondaryLoading = false
                            } else {
                                // Create a new task with delay for debounce
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
            
            // Right panel - results
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
            ToolbarItemGroup(placement: .automatic) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .hoverToolbarIcon()
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .hoverToolbarIcon()
                }
                .buttonStyle(.plain)
                .help("Help")
            }
        }
        .onAppear {
            refreshTitles()
        }
	        .onChange(of: translationService.preferredTargetLanguage) { _, _ in
	            guard translationService.isStarredPrimaryBuiltInTranslate else { return }
	            refreshTitles()
	            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
	                processPrimaryText()
	            }
	        }
	        .onChange(of: translationService.starredPrimarySelectionKey) { _, _ in
	            refreshTitles()
	            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
	                processPrimaryText()
	            }
	        }
	        .onChange(of: translationService.starredSecondaryActionId) { _, _ in
	            refreshTitles()
	            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
	                processSecondaryText()
	            }
	        }
	        .onChange(of: translationService.builtInTranslateModel) { _, _ in
	            guard translationService.isStarredPrimaryBuiltInTranslate else { return }
	            refreshTitles()
	            if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
	                processPrimaryText()
	            }
	        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(translationService)
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .alert("Error", isPresented: Binding(
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
            .hoverHighlight()
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

        let resolvedTargetLanguage = translationService.resolveTargetLanguage(for: text, selectedLanguage: translationService.preferredTargetLanguage)
        primaryNetworkTask?.cancel()
        primaryNetworkTask = translationService.translateText(text: text, targetLanguage: resolvedTargetLanguage, modelOverride: translationService.builtInTranslateModel) { result in
            guard primaryRequestId == requestId else { return }
            isPrimaryLoading = false
            switch result {
            case .success(let text):
                primaryOutputText = text
            case .failure(let error):
                if (error as? URLError)?.code == .cancelled { return }
                primaryOutputText = ""
                translationService.errorMessage = error.localizedDescription
            }
        }
    }

    private var primarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(primaryTitle)
                    .font(.headline)
                Spacer()

                if translationService.isStarredPrimaryBuiltInTranslate {
                    Picker("", selection: $translationService.preferredTargetLanguage) {
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
                .hoverHighlight()
                .help("Copy")
                .disabled(primaryOutputText.isEmpty || isPrimaryLoading)
            }

            .padding(.vertical, 2)

            if isPrimaryLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .frame(width: 36, height: 36)
                    Text("Processing...")
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
                MarkdownTextView(
                    markdown: primaryOutputText,
                    placeholder: "Result will appear here..."
                )
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(secondaryTitle)
                    .font(.headline)
                Spacer()

                Button(action: { copyTextToClipboard(secondaryOutputText) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .hoverHighlight()
                .help("Copy")
                .disabled(secondaryOutputText.isEmpty || isSecondaryLoading)
            }

            .padding(.top, 6)
            .padding(.bottom, 2)

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
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .frame(width: 36, height: 36)
                    Text("Processing...")
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
                MarkdownTextView(
                    markdown: secondaryOutputText,
                    placeholder: "Result will appear here..."
                )
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
        primaryNetworkTask?.cancel()
        secondaryNetworkTask?.cancel()
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
            primaryNetworkTask?.cancel()
            secondaryNetworkTask?.cancel()
            primaryOutputText = ""
            secondaryOutputText = ""
            isPrimaryLoading = false
            isSecondaryLoading = false
	            return
	        }

	        processPrimaryText(using: trimmed)
	        processSecondaryText(using: trimmed)
	    }

	    private func processPrimaryText() {
	        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
	        guard !trimmed.isEmpty else { return }
	        processPrimaryText(using: trimmed)
	    }

	    private func processPrimaryText(using trimmed: String) {
	        let primaryAction = translationService.starredPrimaryCustomAction()
	        if translationService.isStarredPrimaryBuiltInTranslate {
	            runBuiltInTranslate(target: .primary, text: trimmed)
	        } else {
	            runAction(primaryAction, target: .primary, text: trimmed)
	        }
	    }

	    private func processSecondaryText() {
	        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
	        guard !trimmed.isEmpty else { return }
	        processSecondaryText(using: trimmed)
	    }

	    private func processSecondaryText(using trimmed: String) {
	        let secondaryAction = translationService.customActions.first(where: { $0.id == translationService.starredSecondaryActionId })
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

        let resolvedTargetLanguage = translationService.resolveTargetLanguage(for: text, selectedLanguage: translationService.preferredTargetLanguage)
        let resolvedPrompt = prompt.replacingOccurrences(of: "{{targetLanguage}}", with: resolvedTargetLanguage)
        let emptyPromptMessage = "Configure the prompt and model for this action in Settings."

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
            primaryNetworkTask?.cancel()
            primaryNetworkTask = translationService.runCustomAction(text: text, prompt: resolvedPrompt, modelOverride: action.model) { result in
                guard primaryRequestId == requestId else { return }
                isPrimaryLoading = false
                switch result {
                case .success(let text):
                    primaryOutputText = text
                case .failure(let error):
                    if (error as? URLError)?.code == .cancelled { return }
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
            secondaryNetworkTask?.cancel()
            secondaryNetworkTask = translationService.runCustomAction(text: text, prompt: resolvedPrompt, modelOverride: action.model) { result in
                guard secondaryRequestId == requestId else { return }
                isSecondaryLoading = false
                switch result {
                case .success(let text):
                    secondaryOutputText = text
                case .failure(let error):
                    if (error as? URLError)?.code == .cancelled { return }
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
