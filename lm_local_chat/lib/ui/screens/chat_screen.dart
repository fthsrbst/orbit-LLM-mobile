import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../controllers/chat_controller.dart';
import '../../controllers/session_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/animated_background.dart';
import '../widgets/settings_sheet.dart';
import 'connection_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.sessionController,
    required this.chatController,
    required this.settingsController,
  });

  final SessionController sessionController;
  final ChatController chatController;
  final SettingsController settingsController;

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

    _inputController.clear();
    setState(() => _pendingAttachments.clear());

    await widget.chatController.sendMessage(composed);
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
                            collapseModelChip: chat.messages.isNotEmpty,
                          ),
                          if (!session.isReady)
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
    required this.collapseModelChip,
  });

  final SessionController session;
  final VoidCallback onMenuPressed;
  final VoidCallback onModelPressed;
  final VoidCallback onSharePressed;
  final bool collapseModelChip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.displaySmall ??
        theme.textTheme.headlineMedium ??
        const TextStyle(fontSize: 28);

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
                  child: IconButton(
                    icon: const Icon(Icons.ios_share_rounded),
                    tooltip: 'Paylaş',
                    onPressed: onSharePressed,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Text('orbit', style: titleStyle),
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
                  'Orbit modunda sohbet başlatmak için LM Studio sunucusunu bağla.',
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
