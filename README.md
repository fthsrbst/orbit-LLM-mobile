# LM Local Chat (Orbit)

Modern, yerel-öncelikli bir Flutter sohbet istemcisi. iOS ve Android’de çalışır; aynı ağdaki [LM Studio](https://lmstudio.ai) örneklerini otomatik bulur, gerekirse manuel bağlanır ve tamamen çevrimdışı senaryolar için yerel modellere geçişe imkân tanır.

> Not: Proje aktif geliştirme altındadır. 1.0 deneyimini tamamlayana kadar hızlı eklemeler ve ara sıra kırıcı değişiklikler olabilir.

## Öne Çıkanlar

- **Yerel-öncelikli mimari**: Veriler cihazınızda kalır; bulut zorunlu değildir.
- **Anlık akış**: Token bazlı akış ve anlık durum bildirimleri (`tokens/s` dahil).
- **Düşünceli arayüz**: Shader tabanlı arka plan, uyarlanabilir tipografi, iOS/Android’de tutarlı vurgu renkleri.
- **Kalıcı geçmiş**: Sohbetler ve ayarlar cihazda saklanır; kaldığınız yerden devam edin.

## Hızlı Başlangıç

### Gereksinimler

- Flutter 3.35+ (Dart 3.9+)
- iOS için Xcode 15+, Android için en güncel Android Studio
- Orbit modu için aynı LAN üzerinde çalışan LM Studio (opsiyonel)

### Kurulum

```bash
git clone https://github.com/fthsrbst/project.git
cd project/lm_local_chat
flutter pub get
```

### Çalıştırma

```bash
# Cihazları listele
flutter devices

# iOS/Android cihazda çalıştır
flutter run -d <cihaz-id>
```

iOS’ta ilk açılışta **Yerel Ağ** izni istenir; LM Studio keşfi için gereklidir.

## Derleme

### iOS (cihaz)

```bash
cd lm_local_chat
flutter build ios --release
```

Xcode otomatik imzalama açık ise fiziksel cihaz için imzalama kendiliğinden yapılır.

### Android (APK)

```bash
cd lm_local_chat
flutter build apk --release
```

Çıktı: `lm_local_chat/build/app/outputs/flutter-apk/app-release.apk`

## Mimari Özeti

```text
lib/
├── controllers/           # durum yönetimi (ChangeNotifier)
├── services/              # LM Studio köprüsü ve depolama yardımcıları
├── ui/                    # ekranlar ve bileşenler
└── models/                # veri modelleri
```

## Geliştirme

```bash
flutter analyze
flutter test
dart format lib test
```

Başlatıcı ikonlarını güncellemek için:

```bash
flutter pub run flutter_launcher_icons
```

## Lisans

MIT Lisansı. Ayrıntılar için `LICENSE` dosyasına bakın.
