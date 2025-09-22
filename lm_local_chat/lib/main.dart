import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controllers/chat_controller.dart';
import 'controllers/session_controller.dart';
import 'controllers/settings_controller.dart';
import 'services/chat_storage_service.dart';
import 'services/lm_studio_service.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/widgets/animated_background.dart';
import 'l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrbitApp());
}

class OrbitApp extends StatefulWidget {
  const OrbitApp({super.key});

  @override
  State<OrbitApp> createState() => _OrbitAppState();
}

class _OrbitAppState extends State<OrbitApp> {
  late final LmStudioService _service;
  late final SessionController _sessionController;
  late final ChatStorageService _chatStorage;
  late final ChatController _chatController;
  late final SettingsController _settingsController;
  bool _bootstrapped = false;
  String? _lastHost;
  bool _showOnboarding = false;

  static const _onboardingKey = 'orbit_onboarding_seen';

  @override
  void initState() {
    super.initState();
    _service = LmStudioService();
    _sessionController = SessionController(_service);
    _chatStorage = ChatStorageService();
    _chatController = ChatController(
      _service,
      _sessionController,
      _chatStorage,
    );
    _settingsController = SettingsController();
    _sessionController.addListener(_handleSessionChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _settingsController.initialise();
    await _sessionController.initialise();
    await _chatController.initialise();
    _lastHost = _sessionController.host;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool(_onboardingKey) ?? false;
    if (!mounted) return;
    setState(() {
      _bootstrapped = true;
      _showOnboarding = !hasSeenOnboarding;
    });
  }

  void _handleSessionChanged() {
    final host = _sessionController.host;
    if (host != null && host != _lastHost) {
      unawaited(_chatController.startNewChat());
    }
    _lastHost = host;
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    if (mounted) {
      setState(() {
        _showOnboarding = false;
      });
    }
  }

  @override
  void dispose() {
    _sessionController.removeListener(_handleSessionChanged);
    _service.dispose();
    _sessionController.dispose();
    _chatController.dispose();
    _settingsController.dispose();
    super.dispose();
  }

  ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final accent = _settingsController.accentColor;
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF080808) : const Color(0xFFF4F1EC);
    final surfaceContainer = isDark
        ? const Color(0xFF141418)
        : const Color(0xFFE6E1D9);
    final outlineVariant = isDark
        ? const Color(0xFF3F3F3F)
        : const Color(0xFFBEB6A8);

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          surface: surface,
          surfaceContainerHighest: surfaceContainer,
          outlineVariant: outlineVariant,
        );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      textTheme: _buildTypography(base.textTheme, brightness: brightness),
      iconTheme: IconThemeData(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: _bodyTextStyle(
          _settingsController.bodyFont,
          14,
          colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  TextTheme _buildTypography(TextTheme base, {required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final displayColor = isDark ? Colors.white : const Color(0xFF111111);
    final bodyColor = isDark ? Colors.white70 : const Color(0xFF1F1F33);
    final kholic = TextStyle(fontFamily: 'Kholic', color: displayColor);
    final bodyFont = _settingsController.bodyFont;

    return base.copyWith(
      displayLarge: kholic.copyWith(fontSize: 52, letterSpacing: 2),
      displayMedium: kholic.copyWith(fontSize: 40, letterSpacing: 1.4),
      displaySmall: kholic.copyWith(fontSize: 28, letterSpacing: 1.2),
      headlineMedium: kholic.copyWith(fontSize: 22, letterSpacing: 1.1),
      titleLarge: kholic.copyWith(fontSize: 20),
      titleMedium: kholic.copyWith(fontSize: 18),
      titleSmall: kholic.copyWith(fontSize: 15),
      bodyLarge: _bodyTextStyle(bodyFont, 16, bodyColor),
      bodyMedium: _bodyTextStyle(
        bodyFont,
        14,
        bodyColor.withValues(alpha: 0.85),
      ),
      bodySmall: _bodyTextStyle(bodyFont, 12, bodyColor.withValues(alpha: 0.7)),
      labelLarge: kholic.copyWith(fontSize: 16, letterSpacing: 1.4),
    );
  }

  TextStyle _bodyTextStyle(String font, double size, Color color) {
    switch (font) {
      case 'Inter':
        return GoogleFonts.inter(fontSize: size, color: color);
      case 'Space Grotesk':
        return GoogleFonts.spaceGrotesk(fontSize: size, color: color);
      default:
        return GoogleFonts.outfit(fontSize: size, color: color);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settingsController,
      builder: (context, _) {
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.translate('app_title'),
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: _settingsController.themeMode,
          locale: _settingsController.localeOverride,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final scaler = TextScaler.linear(_settingsController.textScale);
            return MediaQuery(
              data: media.copyWith(textScaler: scaler),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: !_bootstrapped
                    ? const _SplashScreen()
                    : ChatScreen(
                        key: const ValueKey('chat'),
                        sessionController: _sessionController,
                        chatController: _chatController,
                        settingsController: _settingsController,
                      ),
              ),
              if (_showOnboarding)
                _OnboardingOverlay(
                  onFinish: _completeOnboarding,
                  useShader: _settingsController.useShader,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('orbit', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 24),
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingOverlay extends StatefulWidget {
  const _OnboardingOverlay({required this.onFinish, required this.useShader});

  final Future<void> Function() onFinish;
  final bool useShader;

  @override
  State<_OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<_OnboardingOverlay> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  static const _slides = <_OnboardingSlideData>[
    _OnboardingSlideData(
      icon: Icons.hub_rounded,
      title: 'Ağ bağlantısı',
      description:
          'LM Studio IP ve port bilgilerini gir, aynı ağdaki sunucuyu otomatik tara.',
    ),
    _OnboardingSlideData(
      icon: Icons.auto_awesome_rounded,
      title: 'Akıllı sohbet',
      description:
          'Modeller arasında geçiş yap, sohbeti sürdür ve token hızını takip et.',
    ),
    _OnboardingSlideData(
      icon: Icons.history_rounded,
      title: 'Geçmiş ve paylaşım',
      description:
          'Sohbetlerini kaydet, paylaş veya yeniden açarak kaldığın yerden devam et.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_currentPage == _slides.length - 1) {
      widget.onFinish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  void _skip() {
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
              child: AnimatedWaveBackground(
                enableShader: widget.useShader,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.55 : 0.8,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: TextButton(
                            onPressed: _skip,
                            child: const Text('Atla'),
                          ),
                        ),
                        SizedBox(
                          height: 280,
                          child: PageView.builder(
                            controller: _controller,
                            itemCount: _slides.length,
                            onPageChanged: (index) {
                              setState(() {
                                _currentPage = index;
                              });
                            },
                            itemBuilder: (context, index) {
                              final slide = _slides[index];
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    slide.icon,
                                    size: 72,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    slide.title,
                                    style: theme.textTheme.displaySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    slide.description,
                                    style: theme.textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        _OnboardingDots(
                          count: _slides.length,
                          current: _currentPage,
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _goNext,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            child: Text(
                              _currentPage == _slides.length - 1
                                  ? 'Başla'
                                  : 'İleri',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingDots extends StatelessWidget {
  const _OnboardingDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          height: 8,
          width: active ? 24 : 10,
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
            borderRadius: BorderRadius.circular(12),
          ),
        );
      }),
    );
  }
}

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}
