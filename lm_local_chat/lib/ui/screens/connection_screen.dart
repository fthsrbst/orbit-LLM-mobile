import 'package:flutter/material.dart';

import '../../controllers/session_controller.dart';
import '../../models/lm_instance.dart';
import '../../controllers/settings_controller.dart';
import '../widgets/animated_background.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    required this.sessionController,
    required this.settingsController,
  });

  final SessionController sessionController;
  final SettingsController settingsController;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    final host = widget.sessionController.host ?? '';
    final port = widget.sessionController.port.toString();
    _hostController = TextEditingController(text: host);
    _portController = TextEditingController(text: port);
    widget.sessionController.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.sessionController.removeListener(_onSessionChanged);
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    final session = widget.sessionController;
    if (session.host != null && session.host != _hostController.text) {
      _hostController.text = session.host!;
    }
    final portString = session.port.toString();
    if (portString != _portController.text) {
      _portController.text = portString;
    }
  }

  Future<void> _discover() async {
    await widget.sessionController.discoverInstances(
      port: int.tryParse(_portController.text) ?? 1234,
    );
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 1234;
    if (host.isEmpty) return;
    await widget.sessionController.setConnection(host: host, port: port);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.sessionController;
    final settings = widget.settingsController;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return AnimatedWaveBackground(
          enableShader: settings.useShader,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return AnimatedBuilder(
                            animation: session,
                            builder: (context, _) {
                              final listHeight = (constraints.maxHeight * 0.45)
                                  .clamp(160, 360)
                                  .toDouble();
                              return SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 24),
                                    Text(
                                      'orbit',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.displaySmall,
                                    ),
                                    const SizedBox(height: 32),

                                    _GlassCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'LM Studio hazırlığı',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "LM Studio'da Developer Mode'u açıp Settings altından \"Serve on local network\" seçeneğini işaretleyin. Ardından \"Reachable at\" satırındaki adresi yukarıya girin.",
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    _GlassCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Sunucu IP',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          _FrostyField(
                                            controller: _hostController,
                                            hintText: '192.168.1.134',
                                            keyboardType: TextInputType.number,
                                          ),
                                          const SizedBox(height: 24),
                                          Text(
                                            'Port',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          _FrostyField(
                                            controller: _portController,
                                            hintText: '1234',
                                            keyboardType: TextInputType.number,
                                          ),
                                          const SizedBox(height: 24),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _ActionButton(
                                                  label: session.isDiscovering
                                                      ? 'Taranıyor...'
                                                      : 'Otomatik Tara',
                                                  onTap: session.isDiscovering
                                                      ? null
                                                      : _discover,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: _ActionButton(
                                                  label: session.isLoadingModels
                                                      ? 'Bağlanılıyor...'
                                                      : 'Bağlan',
                                                  onTap: session.isLoadingModels
                                                      ? null
                                                      : _connect,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    if (session.errorMessage != null)
                                      AnimatedOpacity(
                                        opacity: session.errorMessage != null
                                            ? 1
                                            : 0,
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        child: _GlassCard(
                                          child: Text(
                                            session.errorMessage!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Colors.redAccent,
                                                ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 20),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      child: session.instances.isEmpty
                                          ? _GlassCard(
                                              key: const ValueKey('empty'),
                                              child: SizedBox(
                                                height: listHeight,
                                                child: Center(
                                                  child: Text(
                                                    session.isDiscovering
                                                        ? 'Ağ taranıyor...'
                                                        : 'Ağdaki LM Studio örnekleri burada listelenir.',
                                                    textAlign: TextAlign.center,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodyMedium,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : SizedBox(
                                              height: listHeight,
                                              child: ListView.separated(
                                                physics:
                                                    const BouncingScrollPhysics(),
                                                itemCount:
                                                    session.instances.length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(height: 12),
                                                itemBuilder: (context, index) {
                                                  final instance =
                                                      session.instances[index];
                                                  return _InstanceTile(
                                                    instance: instance,
                                                    onTap: () {
                                                      _hostController.text =
                                                          instance.host;
                                                      _portController.text =
                                                          instance.port
                                                              .toString();
                                                      session.setConnection(
                                                        host: instance.host,
                                                        port: instance.port,
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 32),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InstanceTile extends StatelessWidget {
  const _InstanceTile({required this.instance, this.onTap});

  final LmStudioInstance instance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                instance.displayLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (instance.modelCount != null)
                Text(
                  '${instance.modelCount} model',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          Icon(Icons.chevron_right, color: Theme.of(context).iconTheme.color),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.35 : 0.7,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.4 : 0.6,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: isDark ? 24 : 12,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
    if (onTap != null) {
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: card,
      );
    }
    return card;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onTap != null;
    final theme = Theme.of(context);
    final gradientColors = isEnabled
        ? [theme.colorScheme.primary, theme.colorScheme.secondary]
        : [
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainerHighest,
          ];
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Text(label, style: theme.textTheme.labelLarge),
      ),
    );
  }
}

class _FrostyField extends StatelessWidget {
  const _FrostyField({
    required this.controller,
    this.hintText,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.25 : 0.6,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
