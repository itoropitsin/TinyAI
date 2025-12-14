import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("Help")
                .font(.title2)
                .padding(.top)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("What DeepAI does") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DeepAI is a small macOS utility that sends your text to OpenAI and shows the result in two panels:")
                            Text("• Starred 1: your primary action (for example, “Translate”).")
                            Text("• Starred 2: a custom action you choose (plus extra buttons to run other custom actions).")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Getting started") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1) Open Settings and paste your OpenAI API key.")
                            Text("2) Choose what “Starred 1” does (built‑in Translate or one of your custom actions).")
                            Text("3) Create custom actions: give each button a title, pick a model, and write a short prompt.")
                            Text("Tip: In the main window you can trigger custom actions with ⌘1, ⌘2, ⌘3, …")
                            Text("Tip: Use {{targetLanguage}} in prompts to reuse the language picker (for example: “Translate to {{targetLanguage}} and fix grammar.”).")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Examples (custom action prompts)") {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Example 1 — Summary")
                                    .font(.headline)
                                Text("Prompt: “Summarize the text in 3 bullet points. Keep it under 60 words.”")
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Example 2 — Rewrite")
                                    .font(.headline)
                                Text("Prompt: “Rewrite the text as a polite and concise email. Preserve key details and names.”")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Popup window") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You can also use the Popup hotkey from any app to open a compact window for the selected text.")
                            Text("Configure the hotkey and its trigger mode (single / double press) in Settings.")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Your API key is stored locally on your Mac. Requests are sent to OpenAI only when you run an action.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .hoverHighlight()
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 560, height: 620)
    }
}
