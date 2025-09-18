# Orbit

Orbit is a polished, mobile-first Flutter client for running privacy-friendly AI conversations entirely on your own hardware. It can auto-discover [LM Studio](https://lmstudio.ai) instances on your LAN, fall back to manually defined servers, or switch into an offline mode that drives quantised GGUF models directly on the device.

> ⚠️ Orbit is evolving quickly. Expect new capabilities and occasional breaking changes while we round out the 1.0 experience.

## Why Orbit?

- **Local-first by design** – connect to LM Studio or run quantised models on device; no cloud required.
- **Two focused modes** – *Orbit* (networked streaming) and *Star* (offline inference) with a single tap toggle.
- **Live feedback** – token streaming, contextual statuses, and inline performance hints keep you in the loop.
- **Thoughtful UI** – shader-driven backgrounds, adaptive typography, and accent colours that carry across iOS and Android.
- **Cancelable downloads** – pause or abort large model pulls without leaving orphaned files.
- **Built to persist** – conversations and settings are cached locally so you can resume exactly where you left off.

## Feature Matrix

| Area | Orbit Mode (LM Studio) | Star Mode (Offline) |
| --- | --- | --- |
| Discovery | mDNS broadcast scan + manual override | n/a |
| Model management | Remote list + quick switcher | Local GGUF catalogue (download, cancel, remove, activate) |
| Response handling | SSE streaming with tokens/sec telemetry | On-device llama.cpp runtime with progress logging |
| UX niceties | Animated shader backdrop, history sheet, share/export | Starfield overlay, local model banner, offline guardrails |

## Quick Start

### Prerequisites

- Flutter 3.19 (Dart 3.3) or newer
- Xcode 15+ (for iOS) / Android Studio Electric Eel+ (for Android)
- LM Studio 0.2+ accessible on the same LAN for Orbit mode
- For Star mode, ensure the device has enough storage and the `libllama` binary packaged with `llama_cpp_dart`

Verify your toolchain:

```bash
flutter --version
```

### Clone & bootstrap

```bash
git clone https://github.com/<your-org>/orbit.git
cd orbit
flutter pub get
```

### Launch

```bash
# List devices
devices=$(flutter devices)
echo "$devices"

# Run (replace <device-id> with the desired identifier)
flutter run -d <device-id>
```

On first launch the app will ask for **Local Network** permission on iOS so it can discover LM Studio instances.

## Star Mode: Local Model Workflow

1. Open the mode toggle and switch to **star**.
2. Tap **Modelleri yönet** to open the local model sheet.
3. Pick a descriptor (e.g. *Phi-3 Mini 4K Q4*) and tap **İndir**.
4. Downloads stream with live progress and an **İptal** action; cancelled pulls tidy up partially written files.
5. Once installed, choose **Kullan** to activate the model, then start chatting fully offline.

### Troubleshooting the llama runtime

- The app auto-detects the bundled `libllama` binary shipped with `llama_cpp_dart` based on the current ABI.
- Set `ORBIT_LLAMA_LIBRARY=/path/to/libllama.dylib` (or `.dll`/`.so`) if you need to override the search path.
- Debug logs (visible in `flutter run`) are prefixed with `[LocalInference]` for quick filtering.

## Project Structure

```text
lib/
├── controllers/
│   ├── chat_controller.dart        # Conversation orchestration & persistence
│   ├── local_model_controller.dart # Offline model catalogue & download manager
│   ├── session_controller.dart     # LM Studio discovery, connection, model selection
│   └── settings_controller.dart    # Theme, accent, typography, shader toggles
├── services/
│   ├── lm_studio_service.dart      # REST/SSE bridge to LM Studio
│   └── local_inference_service.dart# llama.cpp integration for Star mode
├── ui/
│   ├── screens/
│   │   ├── chat_screen.dart        # Main chat shell, header, mode toggle
│   │   └── connection_screen.dart  # Onboarding & manual connection flow
│   └── widgets/
│       └── animated_background.dart
└── models/                         # Plain data models for chat + settings
```

## Development

### Useful commands

```bash
flutter pub get
flutter analyze
flutter test
dart format lib test
```

### Regenerating launcher icons

The new `assets/icons/orbit_icon.png` drives all platforms. Regenerate when the asset changes:

```bash
flutter pub run flutter_launcher_icons
```

### Coding guidelines

- Follow the lint configuration in `analysis_options.yaml` (based on `flutter_lints`).
- Keep UI copy bilingual where relevant (TR/EN) across settings and toasts.
- Prefer the existing `ChangeNotifier` pattern to maintain consistency.

## Roadmap

- Curated GGUF bundles with friendly licensing for Star mode out-of-the-box.
- Enhanced markdown rendering (tables, callouts, expandable sections).
- Desktop builds (macOS, Windows, Linux) after the mobile UX stabilises.
- Scenario presets that auto-load prompts and recommended models.

## Contributing

Contributions are welcome! To get involved:

1. Open an Issue for significant proposals so we can align on scope.
2. Fork the repo, branch off `main`, and keep commits focused.
3. Include reproduction steps or manual test notes in pull requests.

## License

Orbit is released under the [MIT License](LICENSE). You are free to use, modify, and distribute it with attribution.

---

Built with ♥️ for developers who value dependable, private AI tooling.
