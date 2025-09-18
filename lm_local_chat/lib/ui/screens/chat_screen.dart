import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../controllers/chat_controller.dart';
import '../../controllers/local_model_controller.dart';
import '../../controllers/session_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../widgets/animated_background.dart';
import 'connection_screen.dart';

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

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final AnimationController _introController;
  late final Animation<double> _blurAnimation;
  late final Animation<double> _fadeAnimation;
  final List<_PendingAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _blurAnimation = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    widget.chatController.addListener(_scrollToBottomOnUpdate);
    unawaited(widget.localModelController.initialise());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _introController.forward();
      }
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
    _introController.dispose();
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
    final rawText = _inputController.text;
    final attachments = List<_PendingAttachment>.from(_pendingAttachments);
    final hasText = rawText.trim().isNotEmpty;
    if (!hasText && attachments.isEmpty) {
      return;
    }

    final composed = _composeMessage(rawText, attachments);
    final settings = widget.settingsController;
    final isStarMode = settings.appMode == AppMode.star;
    final localActive = widget.localModelController.activeModelState;

    if (isStarMode &&
        (localActive == null ||
            localActive.status != LocalModelStatus.installed ||
            localActive.localPath == null)) {
      _showSnackBar(
        'Yerel modeli kullanmak için Modelleri yönet bölümünden bir model indirip etkinleştirin.',
      );
      return;
    }

    _inputController.clear();
    setState(() => _pendingAttachments.clear());

    if (isStarMode) {
      await widget.chatController.sendMessage(
        composed,
        forceOffline: true,
        offlineModelName: localActive!.descriptor.name,
        offlineModelId: localActive.descriptor.id,
        offlineModelPath: localActive.localPath,
      );
    } else {
      await widget.chatController.sendMessage(composed);
    }
  }

  Future<void> _handleShare() async {
    final status = await widget.chatController.shareCurrentSession();
    if (!mounted) return;
    if (status == null) {
      _showSnackBar('Paylaşılacak sohbet bulunamadı.');
      return;
    }
    switch (status) {
      case ShareResultStatus.success:
        break;
      case ShareResultStatus.dismissed:
        _showSnackBar('Paylaşım kapatıldı.');
        break;
      case ShareResultStatus.unavailable:
        _showSnackBar(
          'Paylaşım desteklenmiyor, sohbet metin olarak kopyalandı.',
        );
        break;
    }
  }

  Future<void> _openLocalModels() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: _StarModePanel(
            controller: widget.localModelController,
            onActivate: widget.localModelController.setActiveModel,
          ),
        );
      },
    );
  }

  Future<void> _pickAttachments() async {
    const maxAttachments = 5;
    if (_pendingAttachments.length >= maxAttachments) {
      _showSnackBar('En fazla 5 dosya eklenebilir.');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;
      final files = result.files.where((file) => file.path != null);
      if (files.isEmpty) {
        _showSnackBar('Seçilen dosya okunamadı.');
        return;
      }
      final additions = <_PendingAttachment>[];
      for (final file in files) {
        final path = file.path;
        if (path == null) {
          continue;
        }
        if (_pendingAttachments.any((item) => item.path == path)) {
          continue;
        }
        if (_pendingAttachments.length + additions.length >= maxAttachments) {
          break;
        }
        additions.add(
          _PendingAttachment(
            path: path,
            name: file.name,
            size: file.size,
            sizeLabel: _formatFileSize(file.size),
          ),
        );
      }
      if (additions.isEmpty) {
        _showSnackBar('Yeni dosya eklenmedi.');
        return;
      }
      setState(() {
        _pendingAttachments.addAll(additions);
      });
    } catch (err) {
      _showSnackBar('Dosya seçilirken hata oluştu: $err');
    }
  }

  void _removeAttachment(_PendingAttachment attachment) {
    setState(() {
      _pendingAttachments.removeWhere((item) => item.path == attachment.path);
    });
  }

  String _composeMessage(String input, List<_PendingAttachment> attachments) {
    final trimmed = input.trim();
    if (attachments.isEmpty) {
      return trimmed;
    }
    final buffer = StringBuffer();
    if (trimmed.isNotEmpty) {
      buffer
        ..writeln(trimmed)
        ..writeln();
    }
    buffer.writeln('**Ekler:**');
    for (final attachment in attachments) {
      final uri = Uri.file(attachment.path).toString();
      buffer.writeln('- [${attachment.name}]($uri) · ${attachment.sizeLabel}');
    }
    return buffer.toString().trimRight();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  Future<void> _openHeaderMenu() async {
    final action = await _showBlurDialog<_HeaderMenuAction>(
      builder: (context) => const _MenuCard(
        actions: [
          _HeaderMenuItem(_HeaderMenuAction.history, 'Sohbet geçmişi'),
          _HeaderMenuItem(_HeaderMenuAction.connection, 'Bağlantı'),
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
      case _HeaderMenuAction.connection:
        _openConnection();
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
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SettingsSheet(
          controller: widget.settingsController,
          sessionController: widget.sessionController,
        ),
      ),
    );
  }

  Future<void> _openConnection() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => ConnectionScreen(
          sessionController: widget.sessionController,
          settingsController: widget.settingsController,
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
          enableShader: settings.useShader,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Stack(
              children: [
                if (isStarMode) const _StarfieldOverlay(),
                AnimatedBuilder(
                  animation: _introController,
                  child: Scaffold(
                    backgroundColor: Colors.transparent,
                    body: SafeArea(
                      child: Column(
                        children: [
                          _Header(
                            session: session,
                            onMenuPressed: _openHeaderMenu,
                            onModelPressed: _openModelSelector,
                            onSharePressed: _handleShare,
                            onLocalModelsPressed: isStarMode
                                ? _openLocalModels
                                : null,
                            appMode: settings.appMode,
                            onModeChanged: (mode) =>
                                unawaited(settings.setAppMode(mode)),
                            collapseModelChip: chat.messages.isNotEmpty,
                          ),
                          if (isStarMode)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                              child: _LocalModelBanner(
                                controller: widget.localModelController,
                                onManage: _openLocalModels,
                              ),
                            ),
                          if (!isStarMode && !session.isReady)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                              child: _ConnectionReminder(
                                onConnect: _openConnection,
                              ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: AnimatedBuilder(
                                animation: chat,
                                builder: (context, _) {
                                  final messages = chat.messages;
                                  final statuses = <_InlineStatus>[];
                                  if (session.isLoadingModels) {
                                    statuses.add(
                                      const _InlineStatus(
                                        'Modeller yükleniyor...',
                                        Icons.sync_rounded,
                                      ),
                                    );
                                  }
                                  switch (chat.flowState) {
                                    case ChatFlowState.thinking:
                                      statuses.add(
                                        const _InlineStatus(
                                          'Model düşünüyor...',
                                          Icons.psychology_alt_outlined,
                                        ),
                                      );
                                      break;
                                    case ChatFlowState.generating:
                                      statuses.add(
                                        const _InlineStatus(
                                          'Yanıt yazılıyor...',
                                          Icons.hourglass_bottom_rounded,
                                        ),
                                      );
                                      break;
                                    case ChatFlowState.idle:
                                      break;
                                  }
                                  final showIndicator =
                                      chat.flowState ==
                                          ChatFlowState.generating &&
                                      (messages.isEmpty ||
                                          messages.last.role == ChatRole.user);
                                  final totalCount =
                                      messages.length +
                                      statuses.length +
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
                                        if (index < messages.length) {
                                          final message = messages[index];
                                          final isMe =
                                              message.role == ChatRole.user;
                                          return _MessageBubble(
                                            message: message,
                                            isUser: isMe,
                                          );
                                        }
                                        final statusIndex =
                                            index - messages.length;
                                        if (statusIndex < statuses.length) {
                                          final status = statuses[statusIndex];
                                          return _StatusMessage(status: status);
                                        }
                                        return _TypingBubble(
                                          state: chat.flowState,
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_pendingAttachments.isNotEmpty)
                                  _AttachmentStrip(
                                    attachments: _pendingAttachments,
                                    onRemove: _removeAttachment,
                                  ),
                                Row(
                                  children: [
                                    _AttachButton(
                                      hasAttachments:
                                          _pendingAttachments.isNotEmpty,
                                      onPressed: _pickAttachments,
                                    ),
                                    const SizedBox(width: 12),
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
                                            final hasText =
                                                value.text.trim().isNotEmpty ||
                                                _pendingAttachments.isNotEmpty;
                                            final canSend =
                                                hasText && !isSending;
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
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  builder: (context, child) {
                    final blur = _blurAnimation.value;
                    final opacity = _fadeAnimation.value;
                    Widget content = child!;
                    if (blur > 0.05) {
                      content = ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: blur,
                          sigmaY: blur,
                        ),
                        child: content,
                      );
                    }
                    return Opacity(opacity: opacity, child: content);
                  },
                ),
              ],
            ),
          ),
        );
      },
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

  static final List<Offset> _sparkles = <Offset>[
    const Offset(0.06, 0.12),
    const Offset(0.18, 0.05),
    const Offset(0.32, 0.14),
    const Offset(0.44, 0.08),
    const Offset(0.58, 0.12),
    const Offset(0.7, 0.08),
    const Offset(0.82, 0.16),
    const Offset(0.9, 0.22),
    const Offset(0.08, 0.46),
    const Offset(0.2, 0.58),
    const Offset(0.4, 0.62),
    const Offset(0.68, 0.44),
    const Offset(0.84, 0.48),
    const Offset(0.12, 0.86),
    const Offset(0.28, 0.92),
    const Offset(0.46, 0.9),
    const Offset(0.62, 0.84),
    const Offset(0.8, 0.88),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final glowCenter = Offset(size.width * 0.52, size.height * 0.78);
    final glowRadius = size.width * 0.6;
    final glowShader = RadialGradient(
      colors: [accentColor.withValues(alpha: 0.18), Colors.transparent],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawCircle(glowCenter, glowRadius, Paint()..shader = glowShader);

    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final accentPaint = Paint()..color = accentColor.withValues(alpha: 0.55);

    for (var i = 0; i < _stars.length; i++) {
      final offset = Offset(
        _stars[i].dx * size.width,
        _stars[i].dy * size.height,
      );
      final radius = 1.5 + (i % 3) * 0.8;
      canvas.drawCircle(offset, radius, i.isEven ? accentPaint : starPaint);
    }

    final sparklePaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final accentSparklePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.25);
    for (var i = 0; i < _sparkles.length; i++) {
      final offset = Offset(
        _sparkles[i].dx * size.width,
        _sparkles[i].dy * size.height,
      );
      final radius = 0.6 + (i % 2) * 0.35;
      canvas.drawCircle(
        offset,
        radius,
        i.isEven ? sparklePaint : accentSparklePaint,
      );
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
    required this.collapseModelChip,
    this.onLocalModelsPressed,
  });

  final SessionController session;
  final VoidCallback onMenuPressed;
  final VoidCallback onModelPressed;
  final VoidCallback onSharePressed;
  final AppMode appMode;
  final ValueChanged<AppMode> onModeChanged;
  final bool collapseModelChip;
  final VoidCallback? onLocalModelsPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.ios_share_rounded),
                        tooltip: 'Paylaş',
                        onPressed: onSharePressed,
                      ),
                      if (appMode == AppMode.star &&
                          onLocalModelsPressed != null)
                        IconButton(
                          icon: const Icon(Icons.download_rounded),
                          tooltip: 'Modelleri yönet',
                          onPressed: onLocalModelsPressed,
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: _ModeToggle(mode: appMode, onChanged: onModeChanged),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.grid_view_rounded),
                    tooltip: 'Menü',
                    onPressed: onMenuPressed,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: session,
            builder: (context, _) {
              if (appMode != AppMode.orbit) {
                return const SizedBox.shrink();
              }
              final selected = session.selectedModel;
              final label = selected ?? 'Model seç';
              final isLoading = session.isLoadingModels;
              final collapse = collapseModelChip && selected != null;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: collapse
                    ? _ModelShortcutButton(
                        key: const ValueKey('model-shortcut'),
                        label: label,
                        isLoading: isLoading,
                        onTap: onModelPressed,
                      )
                    : _ModelChip(
                        key: const ValueKey('model-chip'),
                        label: label,
                        isLoading: isLoading,
                        onTap: onModelPressed,
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final AppMode mode;
  final ValueChanged<AppMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeToggleItem(
          label: 'orbit',
          isActive: mode == AppMode.orbit,
          onTap: () => onChanged(AppMode.orbit),
        ),
        const SizedBox(width: 12),
        _ModeToggleItem(
          label: 'star',
          isActive: mode == AppMode.star,
          onTap: () => onChanged(AppMode.star),
        ),
      ],
    );
  }
}

class _ModeToggleItem extends StatelessWidget {
  const _ModeToggleItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        theme.textTheme.displaySmall ??
        theme.textTheme.headlineMedium ??
        const TextStyle(fontSize: 28);
    final activeColor = baseStyle.color ?? theme.colorScheme.onSurface;
    final inactiveColor = activeColor.withValues(alpha: 0.35);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        style: baseStyle.copyWith(
          color: isActive ? activeColor : inactiveColor,
          fontSize: isActive
              ? baseStyle.fontSize
              : (baseStyle.fontSize ?? 28) - 4,
          letterSpacing: isActive ? 1.2 : 0.8,
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: isActive ? 1 : 0.45,
          child: Text(label),
        ),
      ),
    );
  }
}

class _ModelShortcutButton extends StatelessWidget {
  const _ModelShortcutButton({
    super.key,
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
    if (isLoading) {
      return SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: 'Model seç: $label',
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.35 : 0.7,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: const SizedBox(
                height: 44,
                width: 44,
                child: Icon(Icons.memory_rounded),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({
    super.key,
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
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(item.action),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(
                      item.label,
                      style:
                          theme.textTheme.displaySmall?.copyWith(
                            fontSize: 34,
                            letterSpacing: 0.4,
                          ) ??
                          theme.textTheme.titleLarge?.copyWith(
                            fontSize: 34,
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

class _ConnectionReminder extends StatelessWidget {
  const _ConnectionReminder({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.35 : 0.75,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bağlantı yapılandırılmadı',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Orbit modunda sohbet başlatmak için LM Studio sunucusunu bağla veya star moduna geç.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: onConnect,
            child: const Text('Bağlantıyı ayarla'),
          ),
        ],
      ),
    );
  }
}

class _LocalModelBanner extends StatelessWidget {
  const _LocalModelBanner({required this.controller, required this.onManage});

  final LocalModelController controller;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.activeModelState;
        final hasInstalled = controller.models.any(
          (model) => model.status == LocalModelStatus.installed,
        );
        final headline = active != null
            ? 'Aktif model: ${active.descriptor.name}'
            : (hasInstalled
                  ? 'Bir modeli etkinleştir'
                  : 'Yerel model bulunmuyor');
        final description = active != null
            ? 'Yerel sohbet bu model üzerinden çalışır.'
            : (hasInstalled
                  ? 'İndirilen modellerden birini seçerek hemen kullan.'
                  : 'Modelleri indirerek star modunda sohbet edebilirsin.');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.35 : 0.75,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: onManage,
                child: const Text('Modelleri yönet'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StarModePanel extends StatelessWidget {
  const _StarModePanel({required this.controller, required this.onActivate});

  final LocalModelController controller;
  final Future<void> Function(String id) onActivate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final models = controller.models;
        if (models.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight;
            final panelHeight = maxHeight.isFinite
                ? maxHeight.clamp(320.0, 640.0)
                : 520.0;
            return SizedBox(
              height: panelHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Yerel modeller',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: models.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      padding: const EdgeInsets.fromLTRB(4, 20, 4, 24),
                      itemBuilder: (context, index) {
                        final model = models[index];
                        final isActive =
                            controller.activeModelState?.descriptor.id ==
                            model.descriptor.id;
                        return _StarModelTile(
                          state: model,
                          isActive: isActive,
                          onActivate: onActivate,
                          onDownload: () =>
                              controller.startDownload(model.descriptor.id),
                          onCancel: () =>
                              controller.cancelDownload(model.descriptor.id),
                          onRemove: () =>
                              controller.removeModel(model.descriptor.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
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
    required this.isActive,
    required this.onActivate,
    required this.onDownload,
    required this.onCancel,
    required this.onRemove,
  });

  final LocalModelState state;
  final bool isActive;
  final Future<void> Function(String id) onActivate;
  final Future<void> Function() onDownload;
  final Future<void> Function() onCancel;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descriptor = state.descriptor;
    Future<void> activate() => onActivate(descriptor.id);

    Widget actionWidget;
    switch (state.status) {
      case LocalModelStatus.notInstalled:
        actionWidget = FilledButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await onDownload();
            } catch (error) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('İndirme başarısız: $error'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
          },
          child: const Text('İndir'),
        );
        break;
      case LocalModelStatus.downloading:
        final percent = (state.progress * 100).clamp(0, 100).round();
        final indicatorValue = state.progress.clamp(0.0, 1.0);
        actionWidget = FilledButton.tonal(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await onCancel();
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('İndirme iptal edildi.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            } catch (error) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('İptal edilemedi: $error'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: indicatorValue,
                ),
              ),
              const SizedBox(width: 12),
              Text('$percent% • İptal'),
            ],
          ),
        );
        break;
      case LocalModelStatus.installed:
        actionWidget = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            isActive
                ? FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Aktif'),
                  )
                : FilledButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await activate();
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text('${descriptor.name} aktif edildi.'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                    },
                    child: const Text('Kullan'),
                  ),
            OutlinedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await onRemove();
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text('${descriptor.name} kaldırıldı.'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                } catch (error) {
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text('Model kaldırılamadı: $error'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                }
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Kaldır'),
            ),
          ],
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            descriptor.name,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Aktif',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${descriptor.sizeLabel} • ${descriptor.license}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actionWidget,
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
                      final status = await chat.shareSession(session);
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      String feedback;
                      switch (status) {
                        case ShareResultStatus.success:
                          feedback = 'Paylaşım penceresi açıldı.';
                          break;
                        case ShareResultStatus.dismissed:
                          feedback = 'Paylaşım kapatıldı.';
                          break;
                        case ShareResultStatus.unavailable:
                          feedback =
                              'Paylaşım desteklenmiyor, sohbet panoya kopyalandı.';
                          break;
                      }
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(feedback),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
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
          Container(
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
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
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
        tooltip: 'Kopyala',
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          minimumSize: const Size(28, 28),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.copy_rounded, size: 16),
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

class _InlineStatus {
  const _InlineStatus(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.status});

  final _InlineStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.35 : 0.72,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status.icon,
              size: 16,
              color: theme.colorScheme.primary.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 8),
            Text(status.label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.hasAttachments, required this.onPressed});

  final bool hasAttachments;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = hasAttachments
        ? theme.colorScheme.primary
        : theme.iconTheme.color?.withValues(alpha: 0.9);
    return IconButton(
      tooltip: 'Dosya ekle',
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      iconSize: 22,
      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
      icon: Icon(Icons.attach_file_rounded, color: highlight),
    );
  }
}

class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({required this.attachments, required this.onRemove});

  final List<_PendingAttachment> attachments;
  final ValueChanged<_PendingAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: attachments
            .map(
              (attachment) => InputChip(
                label: Text('${attachment.name} • ${attachment.sizeLabel}'),
                onDeleted: () => onRemove(attachment),
                avatar: Icon(
                  Icons.insert_drive_file_rounded,
                  size: 16,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PendingAttachment {
  _PendingAttachment({
    required this.path,
    required this.name,
    required this.size,
    required this.sizeLabel,
  });

  final String path;
  final String name;
  final int size;
  final String sizeLabel;
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
  const _TypingBubble({required this.state});

  final ChatFlowState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.4 : 0.8,
    );
    final label = switch (state) {
      ChatFlowState.thinking => 'Model düşünüyor...',
      ChatFlowState.generating => 'Yanıt yazılıyor...',
      ChatFlowState.idle => 'Hazırlanıyor...',
    };
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
            Text(label, style: theme.textTheme.bodySmall),
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

enum _HeaderMenuAction { history, connection, newChat, settings }

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

  Future<void> _saveManualConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    final host = _manualHostController.text.trim();
    final portValue = int.tryParse(_manualPortController.text.trim());
    if (host.isEmpty || portValue == null) {
      messenger
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
    if (!mounted) return;
    setState(() => _isSavingConnection = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Bağlantı güncellendi'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openLink(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Bağlantı açılamadı: $url'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
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
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      'Ayarlar',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
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
                  onPressed: _isSavingConnection ? null : _saveManualConnection,
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
              const SizedBox(height: 24),
              Divider(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text('Hakkında', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                'Orbit, Fatih tarafından geliştirildi. Daha fazlası için GitHub profilini ziyaret edebilirsin.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => _openLink('https://github.com/fatih'),
                icon: const Icon(Icons.link_rounded),
                label: const Text('github.com/fatih'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
