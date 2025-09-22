# Orbit Local Chat

**Privacy-first, local AI chat client built with Flutter**

[English](#english) | [Türkçe](#türkçe)

---

## English

### Overview

Orbit Local Chat is a modern, privacy-focused Flutter chat application designed for seamless interaction with local AI models. Built with a local-first architecture, it automatically discovers [LM Studio](https://lmstudio.ai) instances on your network while keeping all your data secure on your device.

**Note**: This project is under active development. Expect rapid additions and occasional breaking changes until the 1.0 experience is complete.

### Key Features

- **Privacy-First Architecture**: All conversations remain on your device with no cloud dependency
- **Real-time Streaming**: Token-based streaming with live performance metrics including tokens/s
- **Modern Interface**: 
  - Shader-based backgrounds
  - Adaptive typography
  - Consistent accent colors across iOS and Android platforms
- **Persistent Storage**: Conversations and settings are saved locally for seamless continuation
- **Automatic Discovery**: Finds LM Studio instances on your local network automatically
- **Manual Connection**: Support for custom server configurations
- **Cross-Platform Support**: Native iOS and Android applications

### Technical Requirements

- **Flutter**: 3.35+ (Dart 3.9+)
- **iOS Development**: Xcode 15+
- **Android Development**: Latest Android Studio
- **Optional**: LM Studio running on the same LAN network for Orbit mode

### Installation and Setup

#### Quick Installation

**Download Pre-built APK**: Ready-to-install Android APK files are available in the [Releases](https://github.com/fthsrbst/orbit-local-chat/releases) section. 

- **Latest Version**: [v0.1.0](https://github.com/fthsrbst/orbit-local-chat/releases/tag/v0.1.0)
- Simply download the APK file and install directly on your Android device
- Enable "Install from unknown sources" in your Android settings if prompted

#### Development Environment

```bash
# Clone the repository
git clone https://github.com/fthsrbst/orbit-local-chat.git
cd orbit-local-chat

# Install dependencies
flutter pub get

# List available devices
flutter devices

# Run on target device
flutter run -d <device-id>
```

#### iOS Build

```bash
cd orbit-local-chat
flutter build ios --release
```

**Important**: iOS requires Local Network permission on first launch for LM Studio discovery functionality. Automatic code signing will handle device provisioning if enabled in Xcode.

#### Android Build

```bash
cd orbit-local-chat
flutter build apk --release
```

Output location: `orbit-local-chat/build/app/outputs/flutter-apk/app-release.apk`

### Project Structure

```
lib/
├── controllers/     # State management (ChangeNotifier)
├── services/       # LM Studio bridge and storage utilities
├── ui/            # Screens and UI components
└── models/        # Data models and structures
```

### Development Commands

```bash
# Code analysis
flutter analyze

# Run tests
flutter test

# Code formatting
dart format lib test

# Update launcher icons
flutter pub run flutter_launcher_icons
```

### Configuration

The application supports flexible configuration for various deployment scenarios:

- **Orbit Mode**: Automatic LM Studio discovery on local network
- **Manual Mode**: Direct server connection with custom endpoints
- **Offline Mode**: Local model integration for completely offline scenarios

### Contributing

We welcome contributions to improve Orbit Local Chat. Please ensure all code follows the established patterns and includes appropriate tests.

### License

This project is licensed under the MIT License. See the `LICENSE` file for details.

---

## Türkçe

### Genel Bakış

Orbit Local Chat, yerel AI modelleriyle sorunsuz etkileşim için tasarlanmış modern, gizlilik odaklı bir Flutter sohbet uygulamasıdır. Yerel-öncelikli mimariyle geliştirilmiş olup, ağınızdaki [LM Studio](https://lmstudio.ai) örneklerini otomatik olarak keşfederken tüm verilerinizi cihazınızda güvenli tutar.

**Not**: Bu proje aktif geliştirme altındadır. 1.0 deneyimi tamamlanana kadar hızlı eklemeler ve ara sıra kırıcı değişiklikler bekleyiniz.

### Temel Özellikler

- **Gizlilik-Öncelikli Mimari**: Tüm konuşmalar cihazınızda kalır, bulut bağımlılığı yoktur
- **Gerçek Zamanlı Akış**: Token/saniye dahil canlı performans metrikleriyle token bazlı akış
- **Modern Arayüz**: 
  - Shader tabanlı arka planlar
  - Uyarlanabilir tipografi
  - iOS ve Android platformlarında tutarlı vurgu renkleri
- **Kalıcı Depolama**: Konuşmalar ve ayarlar yerel olarak kaydedilerek kesintisiz devam imkanı
- **Otomatik Keşif**: Yerel ağınızdaki LM Studio örneklerini otomatik bulur
- **Manuel Bağlantı**: Özel sunucu yapılandırmaları için destek
- **Çapraz Platform Desteği**: Native iOS ve Android uygulamaları

### Teknik Gereksinimler

- **Flutter**: 3.35+ (Dart 3.9+)
- **iOS Geliştirme**: Xcode 15+
- **Android Geliştirme**: En güncel Android Studio
- **Opsiyonel**: Orbit modu için aynı LAN ağında çalışan LM Studio

### Kurulum ve Yapılandırma

#### Hızlı Kurulum

**Hazır APK İndirin**: Kuruluma hazır Android APK dosyaları [Releases](https://github.com/fthsrbst/orbit-local-chat/releases) bölümünde mevcuttur.

- **En Son Sürüm**: [v0.1.0](https://github.com/fthsrbst/orbit-local-chat/releases/tag/v0.1.0)
- APK dosyasını indirip doğrudan Android cihazınıza kurabilirsiniz
- İstenirse Android ayarlarınızda "Bilinmeyen kaynaklardan yükleme"yi etkinleştirin

#### Geliştirme Ortamı

```bash
# Repoyu klonlayın
git clone https://github.com/fthsrbst/orbit-local-chat.git
cd orbit-local-chat

# Bağımlılıkları yükleyin
flutter pub get

# Mevcut cihazları listeleyin
flutter devices

# Hedef cihazda çalıştırın
flutter run -d <cihaz-id>
```

#### iOS Yapılandırması

```bash
cd orbit-local-chat
flutter build ios --release
```

**Önemli**: iOS, LM Studio keşif işlevselliği için ilk başlatmada Yerel Ağ izni gerektirir. Xcode'da etkinleştirilmişse otomatik kod imzalama, cihaz provizyon işlemlerini otomatik olarak halleder.

#### Android Yapılandırması

```bash
cd orbit-local-chat
flutter build apk --release
```

Çıktı konumu: `orbit-local-chat/build/app/outputs/flutter-apk/app-release.apk`

### Proje Yapısı

```
lib/
├── controllers/     # Durum yönetimi (ChangeNotifier)
├── services/       # LM Studio köprüsü ve depolama yardımcıları
├── ui/            # Ekranlar ve UI bileşenleri
└── models/        # Veri modelleri ve yapıları
```

### Geliştirme Komutları

```bash
# Kod analizi
flutter analyze

# Testleri çalıştır
flutter test

# Kod formatlama
dart format lib test

# Başlatıcı ikonlarını güncelle
flutter pub run flutter_launcher_icons
```

### Yapılandırma

Uygulama, çeşitli dağıtım senaryoları için esnek yapılandırma desteği sunar:

- **Orbit Modu**: Yerel ağda otomatik LM Studio keşfi
- **Manuel Mod**: Özel uç noktalarla doğrudan sunucu bağlantısı
- **Çevrimdışı Mod**: Tamamen çevrimdışı senaryolar için yerel model entegrasyonu

### Katkıda Bulunma

Orbit Local Chat'i geliştirmek için katkılarınızı bekliyoruz. Lütfen tüm kodların mevcut kalıpları takip ettiğinden ve uygun testler içerdiğinden emin olun.

### Lisans

Bu proje MIT Lisansı altında lisanslanmıştır. Detaylar için `LICENSE` dosyasına bakınız.
