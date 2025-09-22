import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'app_title': 'Orbit',
      'settings_title': 'Settings',
      'settings_close': 'Close',
      'settings_section_general': 'General',
      'settings_section_appearance': 'Appearance',
      'settings_section_chat': 'Chat',
      'settings_section_connection': 'Connection',
      'settings_language_label': 'Language',
      'settings_language_system': 'System default',
      'settings_language_en': 'English',
      'settings_language_tr': 'Turkish',
      'settings_theme_label': 'Theme mode',
      'settings_theme_system': 'System',
      'settings_theme_light': 'Light',
      'settings_theme_dark': 'Dark',
      'settings_text_size': 'Text size',
      'settings_accent_color': 'Accent color',
      'settings_font_label': 'App font',
      'settings_shader_label': 'Animated background',
      'settings_temperature_label': 'Response temperature',
      'settings_connection_host': 'IP address',
      'settings_connection_port': 'Port',
      'settings_connection_save': 'Save connection',
      'settings_connection_invalid': 'Enter a valid IP and port.',
      'settings_connection_saved': 'Connection updated.',
      'settings_about_title': 'About',
      'settings_about_description':
          'Orbit is crafted by Fatih. Visit the GitHub profile for more.',
      'settings_about_action': 'github.com/fatih',
      'settings_link_error': 'Could not open: {url}',
    },
    'tr': {
      'app_title': 'Orbit',
      'settings_title': 'Ayarlar',
      'settings_close': 'Kapat',
      'settings_section_general': 'Genel',
      'settings_section_appearance': 'Görünüm',
      'settings_section_chat': 'Sohbet',
      'settings_section_connection': 'Bağlantı',
      'settings_language_label': 'Dil',
      'settings_language_system': 'Sistem varsayılanı',
      'settings_language_en': 'İngilizce',
      'settings_language_tr': 'Türkçe',
      'settings_theme_label': 'Tema modu',
      'settings_theme_system': 'Sistem',
      'settings_theme_light': 'Açık',
      'settings_theme_dark': 'Koyu',
      'settings_text_size': 'Metin boyutu',
      'settings_accent_color': 'Vurgu rengi',
      'settings_font_label': 'Uygulama fontu',
      'settings_shader_label': 'Animasyonlu arka plan',
      'settings_temperature_label': 'Yanıt sıcaklığı',
      'settings_connection_host': 'IP adresi',
      'settings_connection_port': 'Port',
      'settings_connection_save': 'Bağlantıyı kaydet',
      'settings_connection_invalid': 'Geçerli bir IP ve port giriniz.',
      'settings_connection_saved': 'Bağlantı güncellendi.',
      'settings_about_title': 'Hakkında',
      'settings_about_description':
          'Orbit, Fatih tarafından geliştirildi. Daha fazlası için GitHub profilini ziyaret et.',
      'settings_about_action': 'github.com/fatih',
      'settings_link_error': 'Açılamadı: {url}',
    },
  };

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  String translate(String key) {
    final languageMap = _localizedValues[locale.languageCode];
    if (languageMap != null && languageMap.containsKey(key)) {
      return languageMap[key]!;
    }
    final fallback = _localizedValues['en'];
    if (fallback != null && fallback.containsKey(key)) {
      return fallback[key]!;
    }
    return key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales
        .any((supported) => supported.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) {
    return false;
  }
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
