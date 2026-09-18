# My Local Voice App

Double-click **My Local Voice App** on your Windows desktop. It opens the editable Qwen desktop app and starts the local model and speech services. It uses your last selected LM Studio model; there is no model question in Command Prompt.

Open the conversation panel from the small Qwen orb. The left side has **New chat**, your saved chats, **Transcribe audio**, and the **Local model** selector. Only one chat uses the microphone at a time. Changing models restarts the local voice connection; the app remembers the choice for next launch.

To transcribe a recording, choose **Transcribe audio**, then drop in an audio file or use **Choose audio file**. You can edit, copy, or save the transcript. Expand **Word-by-word timestamps** to inspect timings, or save all timings as a CSV file. This runs on your computer with the already downloaded Parakeet model. The word timings are estimates from the recognizer, so check important passages against the recording.

Your current model, voice and context picks live in `.selected-voice-model`,
`.selected-voice` and `.selected-voice-context`. They are per-machine and stay out of Git, so
switching models no longer shows up as a change to commit. `.selected-voice-model.default` is
the tracked seed both launchers fall back to when the live pick is absent, which is what makes a
fresh clone or a restore start. Edit it if you want a different starting model on a new machine.

The old **Start Local Voice Assistant** shortcut remains available. Use **My Local Voice App** for the new desktop interface.
