# Bonsai support in ZD Voice — 18 September 2026

The launcher now reads `bonsai/official` or `bonsai/crack` from `.selected-voice-model` and starts
the existing Prism runtime through `qwen-audio-agent-editable/desktop/src/bonsai-runtime.mjs`.
It routes speech to localhost:8080/v1 with alias `bonsai`, and reuses a healthy owned server.
Other loaded LM Studio models must be unloaded first. Switching in the app unloads the previous
selected model automatically. Returning to LM Studio stops only the app-owned Bonsai process.

Runtime executable and downloaded GGUFs are not copied or committed. State and logs
`.voice-bonsai-runtime.json*` are ignored. Existing personal model selection is not changed.

Validation: launcher parses in PowerShell; both variants passed real Windows chat and tool-call
API tests at 32768 context, repeated start and shutdown. Source app has 35 passing focused tests
and passing web / isolated Windows package builds (`dist/bonsai-validation`, not launched).
The follow-up below records deployment and desktop verification. No Git push was performed.

## Follow-up deployment
The app has now been rebuilt into its normal installed directory using the supported script.
The live picker exposes both Bonsai variants. Official completed a desktop text response and
the gateway recorded successful audio playback. An existing NLTK redirected-AppData failure
was fixed by copying the cached English tokenizer to `nltk_data/` and setting `NLTK_DATA` for
both launcher and in-app speech restarts. The data folder is machine-local and ignored.
36 focused tests pass. A cold start from the real desktop shortcut with saved Official reached
Standby; Official → CRACK switching and a CRACK desktop reply also passed, with accepted audio
playback. The original Qwen3.5 9B selection was restored. Physical microphone input and a full
OpenCode task remain unverified. Nothing pushed remotely.
