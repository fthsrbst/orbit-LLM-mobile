# LM Local Chat (Orbit)

Yerel-öncelikli, iOS ve Android’de çalışan bir Flutter sohbet uygulaması. Aynı ağdaki [LM Studio](https://lmstudio.ai) örneklerini otomatik keşfeder, manuel bağlantıyı destekler ve çevrimdışı senaryolar için yerel modele geçiş imkânı sunar.

> Not: Proje aktif geliştirme altındadır; hızlı eklemeler ve zaman zaman kırıcı değişiklikler olabilir.

## Öne Çıkanlar

- Yerel-öncelikli: Veriler cihazda tutulur; bulut zorunlu değildir.
- Anlık akış: Token bazlı yayın ve `tokens/s` metrikleri.
- Düşünceli arayüz: Karanlık/açık tema, shader arka plan, vurgu rengi ve tipografi ayarları.
- Kalıcı geçmiş: Sohbetleri cihazda saklar; paylaşın veya temizleyin.

## Kurulum ve Çalıştırma

```bash
cd lm_local_chat
flutter pub get

# Cihazları listele
flutter devices

# Uygulamayı başlat (iOS/Android)
flutter run -d <cihaz-id>
```

iOS’ta ilk açılışta “Yerel Ağ” izni istenir; LM Studio keşfi için gereklidir.

## Derleme

### iOS (release)

```bash
flutter build ios --release
```

### Android (release APK)

```bash
flutter build apk --release
```

Çıktı: `build/app/outputs/flutter-apk/app-release.apk`

## Mimari ve Dizinler

```text
lib/
├── controllers/   # durum ve ayarlar
├── services/      # LM Studio köprüsü, depolama
├── ui/            # ekranlar ve bileşenler
└── models/        # veri modelleri
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
