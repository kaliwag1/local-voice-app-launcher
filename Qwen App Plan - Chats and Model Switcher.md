# Editable Qwen app: chats and model switcher

Goal: a desktop conversation panel with a left sidebar for multiple saved chats and an in-app selector for locally downloaded LM Studio models. Keep the existing local speech, Gemma/OpenCode setup available while developing the editable copy.

1. **Saved chats.** Add an owner-scoped session-summary command using Qwen's existing durable session journal. Return session ID, title from the first user message, and last activity time. Reuse the existing conversation-history command to load a selected chat. Keep the current New Chat action, but make it add a sidebar entry. Start without deletion or simultaneous voice streams.
2. **Sidebar.** Add a collapsible chat list to the desktop conversation panel. Selecting a chat switches the active session, reloads its messages and task cards, and moves the one active microphone connection to that chat. Check that background tasks remain linked to their original chat.
3. **Local model selector.** Add a desktop-only control that lists LLMs downloaded in LM Studio. Reuse the existing launcher switching logic behind a narrow desktop command: stop an active response, load the chosen model, update OpenCode's model, restart the local speech service, and report success or failure. Keep the previous model selected if any step fails. Downloading new models remains in LM Studio.
4. **Verify before daily use.** Test session list/create/switch/restore, model-switch failure recovery, desktop build, and a manual spoken exchange and agent task after switching. Check online search and offline chat. Only replace the current desktop shortcut after the editable app passes those checks.

First useful milestone: saved-chat sidebar. Second milestone: in-app model selector. This reuses Qwen's current session storage and the local model launcher instead of rebuilding the voice stack.
