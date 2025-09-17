import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/lm_instance.dart';

class LmStudioService {
  LmStudioService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<String>> fetchModels({
    required String host,
    required int port,
  }) async {
    final uri = Uri.parse('http://$host:$port/v1/models');
    final response = await _client.get(uri).timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw HttpException('Model list failed with ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'];
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map((model) => model['id'])
          .where((id) => id != null)
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  Future<ChatCompletionResult> sendChatCompletion({
    required String host,
    required int port,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
  }) async {
    final uri = Uri.parse('http://$host:$port/v1/chat/completions');
    final payload = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': temperature,
    });

    final response = await _client
        .post(
          uri,
          headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
          body: payload,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw HttpException('Chat completion failed with ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw StateError('Yanıt boş döndü.');
    }

    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content']?.toString() ?? '';
    final usage = decoded['usage'] as Map<String, dynamic>?;
    final completionTokens = usage?['completion_tokens'] as num?;
    final completionTime = usage?['completion_time'] as num?;
    final tokensPerSecond =
        (completionTokens != null &&
            completionTime != null &&
            completionTime > 0)
        ? completionTokens.toDouble() / completionTime.toDouble()
        : null;

    return ChatCompletionResult(
      content: content,
      tokensPerSecond: tokensPerSecond,
    );
  }

  Stream<ChatStreamChunk> streamChatCompletion({
    required String host,
    required int port,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
  }) async* {
    final uri = Uri.parse('http://$host:$port/v1/chat/completions');
    final request = http.Request('POST', uri)
      ..headers[HttpHeaders.contentTypeHeader] = 'application/json'
      ..body = jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'stream': true,
      });

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw HttpException(
        'Chat completion stream failed with ${response.statusCode}: $body',
      );
    }

    String buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final separatorIndex = buffer.indexOf('\n\n');
        if (separatorIndex == -1) break;
        final rawSegment = buffer.substring(0, separatorIndex).trim();
        buffer = buffer.substring(separatorIndex + 2);
        if (rawSegment.isEmpty) continue;

        for (final line in rawSegment.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final payload = trimmed.startsWith('data:')
              ? trimmed.substring(5).trim()
              : trimmed;
          if (payload == '[DONE]') {
            yield const ChatStreamChunk(done: true);
            return;
          }

          try {
            final decoded = jsonDecode(payload) as Map<String, dynamic>;
            final choices = decoded['choices'];
            if (choices is List && choices.isNotEmpty) {
              final choice = choices.first as Map<String, dynamic>;
              final delta = choice['delta'] as Map<String, dynamic>?;
              final finishReason = choice['finish_reason'];
              final contentPiece = delta?['content']?.toString();
              if (contentPiece != null && contentPiece.isNotEmpty) {
                yield ChatStreamChunk(contentDelta: contentPiece);
              }
              if (finishReason == 'stop') {
                final usage = decoded['usage'] as Map<String, dynamic>?;
                final completionTokens = usage?['completion_tokens'] as num?;
                final completionTime = usage?['completion_time'] as num?;
                final tokensPerSecond =
                    (completionTokens != null &&
                        completionTime != null &&
                        completionTime > 0)
                    ? completionTokens.toDouble() / completionTime.toDouble()
                    : null;
                yield ChatStreamChunk(
                  done: true,
                  tokensPerSecond: tokensPerSecond,
                );
                return;
              }
            }
          } catch (_) {
            // ignore malformed segments
          }
        }
      }
    }

    yield const ChatStreamChunk(done: true);
  }

  Future<List<LmStudioInstance>> discoverInstances({
    int port = 1234,
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final subnets = <String>{};
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        final parts = addr.address.split('.');
        if (parts.length == 4) {
          subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    }
    if (subnets.isEmpty) {
      // common fallback
      subnets.add('192.168.1');
    }

    final results = <LmStudioInstance>[];
    for (final subnet in subnets) {
      final probes = <Future<void>>[];
      const batchSize = 8;
      for (var hostId = 2; hostId < 255; hostId++) {
        final host = '$subnet.$hostId';
        probes.add(
          _probeHost(host, port, timeout).then((count) {
            if (count != null) {
              results.add(
                LmStudioInstance(host: host, port: port, modelCount: count),
              );
            }
          }),
        );
        if (probes.length % batchSize == 0) {
          await Future.wait(probes);
          probes.clear();
        }
      }
      if (probes.isNotEmpty) {
        await Future.wait(probes);
      }
    }

    return results;
  }

  Future<int?> _probeHost(String host, int port, Duration timeout) async {
    try {
      final uri = Uri.parse('http://$host:$port/v1/models');
      final response = await _client
          .get(uri)
          .timeout(timeout, onTimeout: () => http.Response('', 408));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = decoded['data'];
        if (data is List) {
          return data.length;
        }
        return 0;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void dispose() {
    _client.close();
  }
}

class ChatCompletionResult {
  const ChatCompletionResult({required this.content, this.tokensPerSecond});

  final String content;
  final double? tokensPerSecond;
}

class ChatStreamChunk {
  const ChatStreamChunk({
    this.contentDelta,
    this.tokensPerSecond,
    this.done = false,
  });

  final String? contentDelta;
  final double? tokensPerSecond;
  final bool done;
}
