# Orbit

Orbit is a minimalist, mobile-first Flutter client for running fully local AI conversations. It discovers [LM Studio](https://lmstudio.ai) instances on your local network, lets you pick any hosted model, and offers a streaming chat interface tailored for iOS and Android.

> ⚠️ This project is under active development. Expect rapid iteration and breaking changes while we stabilise the roadmap.

## Highlights

- **Local-first AI** – connect to LM Studio over LAN, auto-discover instances, and reuse previously paired hosts.
- **Streaming chat** – responses render token-by-token with inline performance metrics (`tokens/s`).
- **Star modu** – çevrimdışı çalışmak için küçük LLM modellerini indirip yönetin.
- **Minimalist UX** – dark & light themes, shader background toggle, custom accent colour, typography, and text scaling controls.
- **Persistent history** – conversations are stored on-device; revisit, share, or clear them from the history sheet.
- **Model aware** – fetch available models, switch on the fly, monitor status banners (`Thinking…`, `Yanıt oluşturuluyor…`).
- **Onboarding friendly** – animated first-run tour plus landing animation that eases into the chat shell.

## Roadmap

- **Dual runtime modes** – “Orbit” for LM Studio streaming, “Star” for on-device lightweight LLMs (download, manage, run locally).
- **Markdown-rich rendering** – better handling for bold/italic/code blocks, tables, and inline images (partially shipped, expanding coverage).
- **Offline-first** – ship curated, small-footprint models with verified licensing for true airplane-mode usage.
- **Packaging** – TestFlight & Play Store builds once the feature surface stabilises.

Track progress and contribute via [GitHub Issues](../../issues).

## Getting Started

### Prerequisites

- Flutter 3.19+ (Dart 3.3+)
- Xcode 15+ (for iOS) / Android Studio Electric Eel+ (for Android)
- LM Studio running on the same LAN when using Orbit mode

Check your tooling:

```bash
flutter --version
```

### Clone & bootstrap

```bash
git clone https://github.com/<your-org>/orbit.git
cd orbit
flutter pub get
```

### Run

```bash
# iOS (physical device or simulator)
flutter run -d <device-id>

# Androidlutter run -d <android-device>
```

> iOS requires "Local Network" permission on first launch; this is declared in `Info.plist` and surfaced at runtime.

### Configuration

| Setting                         | Where                       | Description |
| ------------------------------- | --------------------------- | ----------- |
| LM Studio host / port           | Connection screen / Settings| Auto-discover or manually set the target LM Studio instance. |
| Theme mode & accent colour      | Settings sheet              | Choose system / light / dark plus accent palette. |
| Body font & text scale          | Settings sheet              | Fine-tune typography for readability. |
| Shader background toggle        | Settings sheet              | Disable GPU shader for battery-sensitive contexts. |
| Temperature slider              | Settings sheet              | Adjust generation creativity for active session. |

All settings & conversations persist via `SharedPreferences`.

## Architecture Overview

```
lib/
├── controllers/
│   ├── chat_controller.dart      # chat state, streaming orchestration, persistence
│   ├── session_controller.dart   # connection discovery, model selection
│   └── settings_controller.dart  # theme, accent, text scale, shader toggle
├── services/
│   ├── lm_studio_service.dart    # HTTP + SSE bridge to LM Studio
│   └── chat_storage_service.dart # SharedPreferences persistence helpers
├── ui/
│   ├── screens/
│   │   ├── chat_screen.dart      # Chat shell + menu overlays
│   │   └── connection_screen.dart# Initial pairing flow
│   └── widgets/
│       └── animated_background.dart
└── models/                       # Plain Dart data objects
```

State flows through lightweight `ChangeNotifier` controllers exposed directly to the UI. Dependencies are constructed in `main.dart` without an external DI container for clarity.

## Development Notes

### Testing

```bash
flutter analyze
flutter test
```

### Launcher icons

`flutter_launcher_icons` is configured. Regenerate assets after editing `assets/icons/orbit_icon.png`:

```bash
flutter pub run flutter_launcher_icons
```

### Code style

- Follow the defaults in `analysis_options.yaml`.
- Run `dart format lib test` before committing.

## Contributing

PRs are welcome! Please:

1. Discuss major changes via an issue first.
2. Write descriptive commit messages.
3. Add tests or manual verification notes where possible.

## License

This project is open source under the [MIT License](LICENSE). Feel free to remix and build upon it.

---

🙏 Thanks for checking out Orbit. If you build a local-first workflow or integrate additional LLM backends, share your story!
