# Your editable Qwen app

The Qwen Audio Agent source is in `qwen-audio-agent-editable`. Its dependencies are installed, and a Windows desktop build completed successfully. The existing **Start Local Voice Assistant** shortcut is separate and still uses your working local setup.

When you want to customise the app, open the source folder in Codex and describe the change you want. The browser interface lives under `web/`; the desktop window and orb live under `desktop/`.

After editing, run `npm run desktop:build:win` from the source folder to produce a Windows installer in `dist/desktop/`. A source build is for local testing and may not carry the same publisher signature as an official release.

Do not run the newly built app alongside the existing Qwen voice window unless you deliberately configure separate voice sessions; the local speech service currently accepts one voice client at a time.
