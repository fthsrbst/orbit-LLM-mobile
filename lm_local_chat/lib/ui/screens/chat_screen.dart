import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../controllers/chat_controller.dart';
import '../../controllers/session_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/local_model_controller.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../widgets/animated_background.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.sessionController,
    required this.chatController,
    required this.settingsController,
    required this.localModelController,
  });

  final SessionController sessionController;
  final ChatController chatController;
  final SettingsController settingsController;
  final LocalModelController localModelController;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  bool _landingAnchoredTop = false;
  bool _landingVisible = true;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    widget.chatController.addListener(_scrollToBottomOnUpdate);
    unawaited(widget.localModelController.initialise());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _landingAnchoredTop = true;
          });
        }
      });
      Future.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) {
          setState(() {
            _landingVisible = false;
          });
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatController != widget.chatController) {
      oldWidget.chatController.removeListener(_scrollToBottomOnUpdate);
      widget.chatController.addListener(_scrollToBottomOnUpdate);
    }
  }

  @override
  void dispose() {
    widget.chatController.removeListener(_scrollToBottomOnUpdate);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomOnUpdate() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleSend() async {
    final text = _inputController.text;
    _inputController.clear();
    await widget.chatController.sendMessage(text);
  }

  Future<void> _openHeaderMenu() async {
    final action = await _showBlurDialog<_HeaderMenuAction>(
      builder: (context) => const _MenuCard(
        actions: [
          _HeaderMenuItem(_HeaderMenuAction.history, 'Sohbet geçmişi'),
          _HeaderMenuItem(_HeaderMenuAction.newChat, 'Yeni sohbet'),
          _HeaderMenuItem(_HeaderMenuAction.settings, 'Ayarlar'),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _HeaderMenuAction.history:
        _showHistorySheet(context, widget.chatController);
        break;
      case _HeaderMenuAction.newChat:
        unawaited(widget.chatController.startNewChat());
        break;
      case _HeaderMenuAction.settings:
        _openSettings();
        break;
    }
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SettingsSheet(
          controller: widget.settingsController,
          sessionController: widget.sessionController,
        ),
      ),
    );
  }

  Future<void> _openModelSelector() async {
    final session = widget.sessionController;
    if (session.isLoadingModels) return;
    final models = session.models;
    if (models.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Model listesi boş. Bağlantıyı kontrol edin.'),
          ),
        );
      return;
    }
    final selected = await _showBlurDialog<String>(
      builder: (context) =>
          _ModelSelectionCard(models: models, current: session.selectedModel),
    );
    if (selected != null) {
      await session.selectModel(selected);
    }
  }

  Future<T?> _showBlurDialog<T>({
    required Widget Function(BuildContext) builder,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      barrierLabel: 'blur',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondary) {
        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () => Navigator.of(context).maybePop(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: GestureDetector(onTap: () {}, child: builder(context)),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = Curves.easeOutBack.transform(animation.value);
        return Opacity(
          opacity: animation.value,
          child: Transform.scale(scale: 0.85 + (0.15 * curved), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.sessionController;
    final chat = widget.chatController;
    final settings = widget.settingsController;

    final isStarMode = settings.appMode == AppMode.star;

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return AnimatedWaveBackground(
          enableShader: settings.useShader && !isStarMode,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Stack(
              children: [
                if (isStarMode) const _StarfieldOverlay(),
                AnimatedOpacity(
                  opacity: _landingAnchoredTop ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Scaffold(
                    backgroundColor: Colors.transparent,
                    body: SafeArea(
                      child: Column(
                        children: [
                          _Header(
                            session: session,
                            onMenuPressed: _openHeaderMenu,
                            onModelPressed: _openModelSelector,
                            onSharePressed: () {
                              unawaited(
                                widget.chatController.shareCurrentSession(),
                              );
                            },
                            appMode: settings.appMode,
                            onModeChanged: (mode) =>
                                unawaited(settings.setAppMode(mode)),
                          ),
                          if (!isStarMode) ...[
                            _StatusBanner(session: session, chat: chat),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: AnimatedBuilder(
                                  animation: chat,
                                  builder: (context, _) {
                                    final messages = chat.messages;
                                    final showIndicator =
                                        chat.flowState != ChatFlowState.idle &&
                                        (messages.isEmpty ||
                                            messages.last.role ==
                                                ChatRole.user);
                                    final totalCount =
                                        messages.length +
                                        (showIndicator ? 1 : 0);
                                    return Listener(
                                      onPointerDown: (_) => FocusManager
                                          .instance
                                          .primaryFocus
                                          ?.unfocus(),
                                      child: ListView.builder(
                                        controller: _scrollController,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 24,
                                        ),
                                        itemCount: totalCount,
                                        itemBuilder: (context, index) {
                                          if (showIndicator &&
                                              index == totalCount - 1) {
                                            return const _TypingBubble();
                                          }
                                          final message = messages[index];
                                          final isMe =
                                              message.role == ChatRole.user;
                                          return _MessageBubble(
                                            message: message,
                                            isUser: isMe,
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            AnimatedBuilder(
                              animation: chat,
                              builder: (context, _) {
                                if (chat.errorMessage == null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _ErrorBanner(
                                    message: chat.errorMessage!,
                                    onDismiss: chat.dismissError,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _ComposerField(
                                      controller: _inputController,
                                      hintText: 'Mesaj yaz...',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: _inputController,
                                    builder: (context, value, _) {
                                      return AnimatedBuilder(
                                        animation: chat,
                                        builder: (context, _) {
                                          final isSending = chat.isSending;
                                          final hasText = value.text
                                              .trim()
                                              .isNotEmpty;
                                          final canSend = hasText && !isSending;
                                          return _CircularSendButton(
                                            isSending: isSending,
                                            onPressed: canSend
                                                ? _handleSend
                                                : null,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 16),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: _StarModePanel(
                                  controller: widget.localModelController,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              child: Text(
                                'Star modu: Küçük LLM modellerini indirip çevrimdışı\nçalıştırmak için kullanılır. İndirilen modeller yakında\nuygulama içinden çalıştırılabilir.',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_landingVisible)
                  _LandingOverlay(anchorToTop: _landingAnchoredTop),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LandingOverlay extends StatefulWidget {
  const _LandingOverlay({required this.anchorToTop});

  final bool anchorToTop;

  @override
  State<_LandingOverlay> createState() => _LandingOverlayState();
}

class _LandingOverlayState extends State<_LandingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fadeOut = widget.anchorToTop;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          alignment: widget.anchorToTop
              ? Alignment.topCenter
              : Alignment.center,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(top: widget.anchorToTop ? 40 : 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              opacity: fadeOut ? 0 : 1,
              child: SizedBox(
                width: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final value = 0.9 + (_pulseController.value * 0.2);
                        return Transform.scale(scale: value, child: child);
                      },
                      child: Container(
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.35),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'orbit',
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 60,
                            letterSpacing: 2.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Local-first intelligence',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            letterSpacing: 0.8,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarfieldOverlay extends StatelessWidget {
  const _StarfieldOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _StarfieldPainter(Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter(this.accentColor);

  final Color accentColor;

  static final List<Offset> _stars = <Offset>[
    const Offset(0.1, 0.2),
    const Offset(0.25, 0.4),
    const Offset(0.48, 0.18),
    const Offset(0.62, 0.55),
    const Offset(0.78, 0.3),
    const Offset(0.88, 0.7),
    const Offset(0.34, 0.75),
    const Offset(0.15, 0.65),
    const Offset(0.55, 0.82),
    const Offset(0.72, 0.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF05060C),
          const Color(0xFF0C1022),
          const Color(0xFF111836),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final accentPaint = Paint()..color = accentColor.withValues(alpha: 0.6);

    for (var i = 0; i < _stars.length; i++) {
      final offset = Offset(
        _stars[i].dx * size.width,
        _stars[i].dy * size.height,
      );
      final radius = 1.5 + (i % 3) * 0.8;
      canvas.drawCircle(offset, radius, i.isEven ? accentPaint : starPaint);
    }

    final arcPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width * 0.52, size.height * 0.78),
      radius: size.width * 0.55,
    );
    canvas.drawArc(rect, 0.1, 1.1, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor;
  }
}

Future<void> _showHistorySheet(BuildContext context, ChatController chat) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: _HistorySheet(chat: chat),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.onMenuPressed,
    required this.onModelPressed,
    required this.onSharePressed,
    required this.appMode,
    required this.onModeChanged,
  });

  final SessionController session;
  final VoidCallback onMenuPressed;
  final VoidCallback onModelPressed;
  final VoidCallback onSharePressed;
  final AppMode appMode;
  final ValueChanged<AppMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Paylaş',
                  onPressed: onSharePressed,
                ),
                Expanded(
                  child: Center(
                    child: Text('orbit', style: theme.textTheme.displaySmall),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.grid_view_rounded),
                  tooltip: 'Menü',
                  onPressed: onMenuPressed,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<AppMode>(
            segments: const [
              ButtonSegment(value: AppMode.orbit, label: Text('Orbit')),
              ButtonSegment(value: AppMode.star, label: Text('Star')),
            ],
            selected: {appMode},
            onSelectionChanged: (value) => onModeChanged(value.first),
          ),
          const SizedBox(height: 16),
          if (appMode == AppMode.orbit)
            AnimatedBuilder(
              animation: session,
              builder: (context, _) {
                final selected = session.selectedModel;
                final isLoading = session.isLoadingModels;
                return _ModelChip(
                  label: selected ?? 'Model seç',
                  isLoading: isLoading,
                  onTap: onModelPressed,
                );
              },
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              child: Text(
                'Star modu • Yerel modelleri indir ve çevrimdışı sohbet et.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 12),
            isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  )
                : Icon(Icons.expand_more_rounded, color: theme.iconTheme.color),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.session, required this.chat});

  final SessionController session;
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    String? label;
    IconData? icon;

    if (session.isLoadingModels) {
      label = 'Modeller yükleniyor...';
      icon = Icons.sync_rounded;
    } else {
      switch (chat.flowState) {
        case ChatFlowState.thinking:
          label = 'Thinking...';
          icon = Icons.psychology_alt_outlined;
          break;
        case ChatFlowState.generating:
          label = 'Yanıt oluşturuluyor...';
          icon = Icons.hourglass_bottom_rounded;
          break;
        case ChatFlowState.idle:
          break;
      }
    }

    if (label == null) {
      return const SizedBox(height: 12);
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Container(
          key: ValueKey(label),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: theme.iconTheme.color?.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.actions});

  final List<_HeaderMenuItem> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: actions
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(item.action),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      alignment: Alignment.center,
                    ),
                    child: Text(
                      item.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 20,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ModelSelectionCard extends StatelessWidget {
  const _ModelSelectionCard({required this.models, required this.current});

  final List<String> models;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: models.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final model = models[index];
              final selected = model == current;
              return ListTile(
                title: Text(
                  model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: selected
                    ? Icon(
                        Icons.check_rounded,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(model),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.chat});

  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: chat,
      builder: (context, _) {
        final sessions = chat.history;
        if (sessions.isEmpty) {
          return SizedBox(
            height: 220,
            child: Center(
              child: Text(
                'Henüz kayıtlı sohbet yok.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          );
        }
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: ListView.separated(
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return _HistoryTile(chat: chat, session: session);
            },
          ),
        );
      },
    );
  }
}

class _StarModePanel extends StatelessWidget {
  const _StarModePanel({required this.controller});

  final LocalModelController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final models = controller.models;
        if (models.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.separated(
          itemCount: models.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemBuilder: (context, index) {
            final model = models[index];
            return _StarModelTile(
              state: model,
              onDownload: () => controller.startDownload(model.descriptor.id),
              onRemove: () => controller.removeModel(model.descriptor.id),
            );
          },
        );
      },
    );
  }
}

class _StarModelTile extends StatelessWidget {
  const _StarModelTile({
    required this.state,
    required this.onDownload,
    required this.onRemove,
  });

  final LocalModelState state;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descriptor = state.descriptor;

    Widget actionButton;
    switch (state.status) {
      case LocalModelStatus.notInstalled:
        actionButton = FilledButton(
          onPressed: onDownload,
          child: const Text('İndir'),
        );
        break;
      case LocalModelStatus.downloading:
        actionButton = FilledButton.tonal(
          onPressed: null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: state.progress,
                ),
              ),
              const SizedBox(width: 12),
              Text('${(state.progress * 100).round()}%'),
            ],
          ),
        );
        break;
      case LocalModelStatus.installed:
        actionButton = OutlinedButton.icon(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Kaldır'),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(descriptor.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${descriptor.sizeLabel} • ${descriptor.license}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actionButton,
            ],
          ),
          const SizedBox(height: 12),
          Text(descriptor.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            descriptor.sourceUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.chat, required this.session});

  final ChatController chat;
  final ChatSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timestamp = session.createdAt.toLocal().toString().split('.').first;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await chat.loadSession(session.id);
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(timestamp, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      '${session.messages.length} mesaj',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Paylaş',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () async {
                      await chat.shareSession(session);
                    },
                  ),
                  IconButton(
                    tooltip: 'Sil',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      await chat.deleteSession(session.id);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isUser});

  final ChatMessage message;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isUser
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.9)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85);
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      color: isUser
          ? theme.colorScheme.onPrimaryContainer
          : theme.colorScheme.onSurfaceVariant,
    );

    return Align(
      alignment: alignment,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey(
                message.timestamp.millisecondsSinceEpoch ^
                    message.content.hashCode,
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(24),
                  topRight: const Radius.circular(24),
                  bottomLeft: Radius.circular(isUser ? 18 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 18),
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.2,
                  ),
                ),
              ),
              child: MarkdownBody(
                data: message.content.isEmpty ? ' ' : message.content,
                shrinkWrap: true,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: textStyle,
                  strong: textStyle?.copyWith(fontWeight: FontWeight.w700),
                  em: textStyle?.copyWith(fontStyle: FontStyle.italic),
                  code: textStyle?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.25),
                  ),
                  codeblockPadding: const EdgeInsets.all(12),
                  codeblockDecoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(
                        color: theme.colorScheme.primary.withValues(alpha: 0.6),
                        width: 3,
                      ),
                    ),
                  ),
                ),
                onTapLink: (text, href, title) {
                  if (href == null) return;
                  Clipboard.setData(ClipboardData(text: href));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          'Bağlantı panoya kopyalandı',
                          style: theme.textTheme.bodyMedium,
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                },
              ),
            ),
          ),
          const SizedBox(height: 2),
          _BubbleFooter(message: message, isUser: isUser),
        ],
      ),
    );
  }
}

class _BubbleFooter extends StatelessWidget {
  const _BubbleFooter({required this.message, required this.isUser});

  final ChatMessage message;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokensText = !isUser && message.tokensPerSecond != null
        ? '${message.tokensPerSecond!.toStringAsFixed(2)} token/sn'
        : null;
    final children = <Widget>[
      IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
        iconSize: 18,
        tooltip: 'Kopyala',
        icon: const Icon(Icons.copy_rounded),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: message.content));
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Metin panoya kopyalandı',
                  style: theme.textTheme.bodyMedium,
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 1),
              ),
            );
        },
      ),
    ];
    if (tokensText != null) {
      children.insert(
        0,
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(tokensText, style: theme.textTheme.bodySmall),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _ComposerField extends StatelessWidget {
  const _ComposerField({required this.controller, required this.hintText});

  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.25 : 0.6,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: 5,
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: theme.textTheme.bodyMedium,
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _CircularSendButton extends StatelessWidget {
  const _CircularSendButton({required this.isSending, this.onPressed});

  final bool isSending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: isSending
                ? [
                    theme.colorScheme.surfaceContainerHighest,
                    theme.colorScheme.surfaceContainerHighest,
                  ]
                : [theme.colorScheme.primary, theme.colorScheme.secondary],
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.35 : 0.1,
              ),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: isSending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.arrow_upward, color: theme.colorScheme.onPrimary),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
            Icon(Icons.close, color: theme.colorScheme.error),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.4 : 0.8,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('Orbit düşünüyor...', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _HeaderMenuItem {
  const _HeaderMenuItem(this.action, this.label);

  final _HeaderMenuAction action;
  final String label;
}

enum _HeaderMenuAction { history, newChat, settings }

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.controller,
    required this.sessionController,
  });

  final SettingsController controller;
  final SessionController sessionController;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  static const _accentOptions = <Color>[
    Color(0xFF6C6CFF),
    Color(0xFF4DD0E1),
    Color(0xFFFF7043),
    Color(0xFF7E57C2),
    Color(0xFF26C6DA),
  ];

  static const _fontOptions = <String>['Outfit', 'Inter', 'Space Grotesk'];

  late final TextEditingController _manualHostController;
  late final TextEditingController _manualPortController;
  bool _isSavingConnection = false;

  @override
  void initState() {
    super.initState();
    final session = widget.sessionController;
    _manualHostController = TextEditingController(text: session.host ?? '');
    _manualPortController = TextEditingController(
      text: session.port.toString(),
    );
  }

  @override
  void dispose() {
    _manualHostController.dispose();
    _manualPortController.dispose();
    super.dispose();
  }

  Future<void> _saveManualConnection(BuildContext context) async {
    final host = _manualHostController.text.trim();
    final portValue = int.tryParse(_manualPortController.text.trim());
    if (host.isEmpty || portValue == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Geçerli bir IP ve port giriniz.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    setState(() => _isSavingConnection = true);
    await widget.sessionController.setConnection(host: host, port: portValue);
    if (!context.mounted) return;
    setState(() => _isSavingConnection = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Bağlantı güncellendi'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ayarlar',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text('Tema modu', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Sistem')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Açık')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Koyu')),
                ],
                selected: {controller.themeMode},
                onSelectionChanged: (value) =>
                    controller.setThemeMode(value.first),
              ),
              const SizedBox(height: 24),
              Text('Vurgu rengi', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _accentOptions
                    .map(
                      (color) => GestureDetector(
                        onTap: () => controller.setAccentColor(color),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                            border: Border.all(
                              color: controller.accentColor == color
                                  ? theme.colorScheme.onPrimary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              Text('Gövde fontu', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: controller.bodyFont,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: _fontOptions
                    .map(
                      (font) =>
                          DropdownMenuItem(value: font, child: Text(font)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    controller.setBodyFont(value);
                  }
                },
              ),
              const SizedBox(height: 24),
              Text('Metin boyutu', style: theme.textTheme.titleMedium),
              Slider(
                value: controller.textScale,
                min: 0.9,
                max: 1.3,
                divisions: 8,
                label: controller.textScale.toStringAsFixed(2),
                onChanged: (value) => controller.setTextScale(value),
              ),
              const SizedBox(height: 24),
              Text('Yanıt sıcaklığı', style: theme.textTheme.titleMedium),
              Slider(
                value: widget.sessionController.temperature,
                min: 0.1,
                max: 1.5,
                divisions: 14,
                label: widget.sessionController.temperature.toStringAsFixed(2),
                onChanged: (value) =>
                    widget.sessionController.updateTemperature(value),
              ),
              const SizedBox(height: 24),
              Text('Manuel bağlantı', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _manualHostController,
                      decoration: const InputDecoration(
                        labelText: 'IP adresi',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _manualPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _isSavingConnection
                      ? null
                      : () => _saveManualConnection(context),
                  child: _isSavingConnection
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Bağlantıyı kaydet'),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                title: const Text('Shader arka planı kullan'),
                value: controller.useShader,
                onChanged: (value) => controller.setShaderEnabled(value),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
