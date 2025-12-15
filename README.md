# TinyAI (macOS)

TinyAI is a lightweight helper for everyday writing: translate, rewrite, fix grammar, summarize, and turn rough text into something you can send—without leaving what you’re doing.

It works in two ways:

- A **main window** where you can paste longer text and keep working.
- A **popup** you can open from *any app* for the text you’ve selected.

## What it’s good for

- **Translation you can trust in context**: pick a target language, keep terminology consistent, and quickly copy the result.
- **Polish before you send**: tighten emails, improve tone, and fix grammar without rewriting everything yourself.
- **Instant summaries**: convert long messages or notes into a few bullets.
- **Reusable “buttons” for your workflow**: create up to 5 custom actions like “Rewrite politely”, “Make it shorter”, “Create meeting notes”, or “Explain like I’m new”.

## How it helps (benefits)

- **Faster flow**: no tab switching—select text, run an action, copy/replace, continue.
- **Consistent style**: save prompts once and reuse them every day.
- **One app, many jobs**: translate + rewrite + summarize + custom prompts, all in one place.

## Quick start

1. Build and run from Xcode (`TinyAI.xcodeproj`).
2. Open **Settings** and paste your **OpenAI API key**.
3. Choose what **Starred 1** and **Starred 2** do (Translate or one of your custom actions).

## Tips

- Start with **Starred 1 = Translate** and **Starred 2 = Polite email** (or Summary). You’ll get value immediately.
- If you use the popup, pick a hotkey you won’t hit by accident (Settings lets you choose single vs double press).

## Everyday use

### Main window (for longer text)

- Paste text into **Source text**.
- Results appear on the right:
  - **Starred 1**: your primary action (often Translate)
  - **Starred 2**: a second action you like (often Rewrite / Grammar fix / Summary)
- Trigger custom actions with **⌘1 … ⌘5**.

### Popup (works from any app)

- Select text in any app and trigger the popup (default: **double‑press ⌘C**).
- Use **Copy** to copy the result, or **Replace** to replace the selected text directly.
- Change the popup hotkey and trigger mode (single/double press) in **Settings**.

## Example custom actions (prompts)

- **Make it shorter**: “Rewrite the text to be 30% shorter, keep meaning, keep proper nouns.”
- **Polite email**: “Rewrite as a polite, concise email. Preserve names, dates, and action items.”
- **Summary**: “Summarize in 3 bullet points. Include decisions and next steps.”
- **Fix grammar**: “Fix grammar and punctuation. Don’t change the tone.”

### Prompt tip

Use `{{targetLanguage}}` inside a custom prompt to reuse the language picker, for example:

`Translate to {{targetLanguage}} and improve grammar, keeping the tone natural.`

## Permissions (one-time)

For the popup hotkey and “Replace” to work from other apps, macOS may ask you to allow **Accessibility** access.

- System Settings → Privacy & Security → Accessibility → enable TinyAI

If you just enabled it, quit and relaunch TinyAI.

## Privacy

- Your API key is stored locally in **macOS Keychain**.
- TinyAI only sends text to OpenAI when you run an action.
