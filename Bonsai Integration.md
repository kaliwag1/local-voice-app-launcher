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
Rebuild the app via `Rebuild My Voice App.cmd` before using the picker.
Desktop switching, voice, OpenCode task and cold-launch validation still need a user-session check.
No deployment or Git push was performed.
