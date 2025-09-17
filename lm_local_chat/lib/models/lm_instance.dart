class LmStudioInstance {
  const LmStudioInstance({
    required this.host,
    required this.port,
    this.modelCount,
  });

  final String host;
  final int port;
  final int? modelCount;

  String get displayLabel => '$host:$port';
}
