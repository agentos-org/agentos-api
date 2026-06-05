/// Normalizes quirky upstream chat SSE into canonical OpenAI-style events,
/// so downstream clients only need to speak vanilla OpenAI.
///
/// OpenAI-"compatible" providers diverge from the OpenAI wire in small but
/// breaking ways. Observed in the wild:
///   - Alibaba Bailian (DashScope, e.g. `deepseek-v4-flash`) frames events as
///     `data:` with NO space. A strict client that matches `"data: "` drops
///     every chunk and sees an empty `content` even though the answer is
///     present — surfacing as "model only produced reasoning, no answer".
///   - Reasoning text arrives under `reasoning_content` (DeepSeek / Kimi) on
///     some providers and `reasoning` (Qwen-flavored) on others.
///   - Streaming `tool_calls` continuation chunks carry empty-string `id` /
///     `function.name` instead of omitting them (Bailian), tripping naive
///     accumulators into starting a brand-new tool call.
///
/// The transform re-frames every event as `data: <json>\n\n`, folds the
/// reasoning field into `reasoning_content`, and strips empty tool-call
/// `id` / `name` on continuation chunks. `[DONE]` and any non-`data:` lines
/// pass through. On a parse failure the original payload is preserved (only
/// the framing is fixed).
library;

import 'dart:convert';

/// Streaming wrapper around [normalizeChatSseText].
///
/// Buffers at the byte level and decodes only complete events (split on the
/// blank-line boundary) so multibyte UTF-8 is never cut across network
/// chunks. Supports both `\n\n` and `\r\n\r\n` event delimiters.
Stream<List<int>> normalizeChatSseStream(Stream<List<int>> source) async* {
  final buffer = <int>[];
  await for (final chunk in source) {
    buffer.addAll(chunk);
    final boundary = _lastEventBoundary(buffer);
    if (boundary < 0) continue;
    final complete = buffer.sublist(0, boundary);
    final remainder = buffer.sublist(boundary);
    buffer
      ..clear()
      ..addAll(remainder);
    final normalized = normalizeChatSseText(
      utf8.decode(complete, allowMalformed: true),
    );
    if (normalized.isNotEmpty) yield utf8.encode(normalized);
  }
  if (buffer.isNotEmpty) {
    final normalized = normalizeChatSseText(
      utf8.decode(buffer, allowMalformed: true),
    );
    if (normalized.isNotEmpty) yield utf8.encode(normalized);
  }
}

/// Index just past the last SSE event boundary (`\n\n` or `\r\n\r\n`) in
/// [bytes], or -1 when no complete event has arrived yet. Newlines are ASCII
/// so a raw byte scan is UTF-8 safe.
int _lastEventBoundary(List<int> bytes) {
  for (var i = bytes.length - 1; i >= 1; i--) {
    if (bytes[i] != 0x0A) continue;
    if (bytes[i - 1] == 0x0A) return i + 1; // \n\n
    if (i >= 3 &&
        bytes[i - 1] == 0x0D &&
        bytes[i - 2] == 0x0A &&
        bytes[i - 3] == 0x0D) {
      return i + 1; // \r\n\r\n
    }
  }
  return -1;
}

/// Normalizes a run of one or more complete SSE events (the pure, testable
/// core of [normalizeChatSseStream]).
String normalizeChatSseText(String text) {
  final out = StringBuffer();
  for (final event in text.replaceAll('\r\n', '\n').split('\n\n')) {
    if (event.isEmpty) continue;
    final normalizedLines = <String>[];
    for (final line in event.split('\n')) {
      if (line.isEmpty) continue;
      normalizedLines.add(_normalizeSseLine(line));
    }
    if (normalizedLines.isEmpty) continue;
    out
      ..writeAll(normalizedLines, '\n')
      ..write('\n\n');
  }
  return out.toString();
}

/// Normalizes one SSE line. Non-`data:` lines pass through unchanged.
String _normalizeSseLine(String line) {
  if (!line.startsWith('data:')) return line;
  var payload = line.substring(5);
  if (payload.startsWith(' ')) payload = payload.substring(1);
  payload = payload.trim();
  if (payload.isEmpty) return 'data:';
  if (payload == '[DONE]') return 'data: [DONE]';
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      _normalizeChatChunk(decoded);
      return 'data: ${jsonEncode(decoded)}';
    }
  } catch (_) {
    // Not JSON we understand — keep the payload, fix only the framing.
  }
  return 'data: $payload';
}

/// Applies OpenAI-canonical normalization to a streaming chunk in place.
void _normalizeChatChunk(Map<String, dynamic> chunk) {
  final choices = chunk['choices'];
  if (choices is! List) return;
  for (final choice in choices) {
    if (choice is! Map) continue;
    final delta = choice['delta'];
    if (delta is Map<String, dynamic>) normalizeOpenAiMessage(delta);
    final message = choice['message'];
    if (message is Map<String, dynamic>) normalizeOpenAiMessage(message);
  }
}

/// Rewrites a single `delta` / `message` object to the canonical OpenAI
/// shape. Returns whether anything changed (lets the non-streaming path skip
/// a needless re-encode).
bool normalizeOpenAiMessage(Map<String, dynamic> obj) {
  var mutated = false;

  // Unify the reasoning field name. `reasoning_content` is the dominant
  // OpenAI-compatible convention (DeepSeek / vLLM / SGLang) and is what
  // ModelKit already speaks internally, so fold `reasoning` into it.
  if (obj.containsKey('reasoning') && !obj.containsKey('reasoning_content')) {
    obj['reasoning_content'] = obj.remove('reasoning');
    mutated = true;
  }

  // Drop empty-string tool-call id / name on continuation chunks so a strict
  // accumulator doesn't mistake them for the start of a new call.
  final toolCalls = obj['tool_calls'];
  if (toolCalls is List) {
    for (final tc in toolCalls) {
      if (tc is! Map) continue;
      if (tc['id'] is String && (tc['id'] as String).isEmpty) {
        tc.remove('id');
        mutated = true;
      }
      final fn = tc['function'];
      if (fn is Map && fn['name'] is String && (fn['name'] as String).isEmpty) {
        fn.remove('name');
        mutated = true;
      }
    }
  }

  return mutated;
}

/// Normalizes a full (non-streaming) chat completion JSON body. Returns the
/// original bytes unchanged on any failure or when nothing needed rewriting.
List<int> normalizeChatJsonBody(List<int> bytes) {
  if (bytes.isEmpty) return bytes;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) return bytes;
    final choices = decoded['choices'];
    if (choices is! List) return bytes;
    var mutated = false;
    for (final choice in choices) {
      if (choice is! Map) continue;
      final message = choice['message'];
      if (message is Map<String, dynamic> && normalizeOpenAiMessage(message)) {
        mutated = true;
      }
    }
    if (!mutated) return bytes;
    return utf8.encode(jsonEncode(decoded));
  } catch (_) {
    return bytes;
  }
}
