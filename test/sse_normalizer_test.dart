import 'dart:convert';

import 'package:agentos_api/src/services/modelkit/sse_normalizer.dart';
import 'package:test/test.dart';

/// Extracts the concatenated `delta.content` from a normalized SSE blob using
/// a *strict* OpenAI parser (the kind a third-party app like wynn-wiki uses:
/// it only accepts `"data: "` with a space and only reads `delta.content`).
String strictOpenAiContent(String sse) {
  final out = StringBuffer();
  for (final line in sse.split('\n')) {
    if (!line.startsWith('data: ')) continue; // note the required space
    final payload = line.substring(6).trim();
    if (payload == '[DONE]') continue;
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) continue;
    final delta = (choices.first as Map<String, dynamic>)['delta']
        as Map<String, dynamic>?;
    final content = delta?['content'];
    if (content is String) out.write(content);
  }
  return out.toString();
}

String strictOpenAiReasoning(String sse) {
  final out = StringBuffer();
  for (final line in sse.split('\n')) {
    if (!line.startsWith('data: ')) continue;
    final payload = line.substring(6).trim();
    if (payload == '[DONE]') continue;
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) continue;
    final delta = (choices.first as Map<String, dynamic>)['delta']
        as Map<String, dynamic>?;
    final r = delta?['reasoning_content'];
    if (r is String) out.write(r);
  }
  return out.toString();
}

void main() {
  group('normalizeChatSseText — Bailian (DashScope) format', () {
    // Bailian frames events as `data:` with NO space, puts reasoning in
    // `reasoning_content`, and answer in `content`.
    const bailian =
        'data:{"choices":[{"delta":{"content":null,"reasoning_content":"用户","role":"assistant"},"index":0}],"object":"chat.completion.chunk"}\n\n'
        'data:{"choices":[{"delta":{"content":null,"reasoning_content":"问了两个问题"},"index":0}],"object":"chat.completion.chunk"}\n\n'
        'data:{"choices":[{"delta":{"content":"好的，","reasoning_content":null},"index":0}],"object":"chat.completion.chunk"}\n\n'
        'data:{"choices":[{"delta":{"content":"我来处理。","reasoning_content":null},"index":0}],"object":"chat.completion.chunk"}\n\n'
        'data:[DONE]\n\n';

    test('adds the missing space after `data:`', () {
      final normalized = normalizeChatSseText(bailian);
      expect(normalized.contains('data:{'), isFalse);
      for (final line in normalized.split('\n')) {
        if (line.isEmpty) continue;
        expect(line.startsWith('data: '), isTrue, reason: 'line: $line');
      }
    });

    test('a strict OpenAI parser now recovers the answer content', () {
      // This is the exact failure mode: before normalization the strict
      // parser saw 0 content (because of `data:` no-space) and only
      // reasoning, producing the false "no answer" error.
      final normalized = normalizeChatSseText(bailian);
      expect(strictOpenAiContent(normalized), '好的，我来处理。');
      expect(strictOpenAiReasoning(normalized), '用户问了两个问题');
    });

    test('preserves the [DONE] terminator', () {
      final normalized = normalizeChatSseText(bailian);
      expect(normalized.contains('data: [DONE]'), isTrue);
    });
  });

  group('normalizeChatSseText — Qwen (OpenAI-style) format', () {
    // Qwen uses `data: ` with a space, but reasoning under `reasoning`.
    const qwen =
        'data: {"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}\n\n'
        'data: {"choices":[{"index":0,"delta":{"reasoning":"用户"}}]}\n\n'
        'data: {"choices":[{"index":0,"delta":{"reasoning":"想了解天气"}}]}\n\n'
        'data: {"choices":[{"index":0,"delta":{"content":"北京"}}]}\n\n'
        'data: {"choices":[{"index":0,"delta":{"content":"晴。"}}]}\n\n'
        'data: [DONE]\n\n';

    test('folds `reasoning` into `reasoning_content`', () {
      final normalized = normalizeChatSseText(qwen);
      expect(normalized.contains('"reasoning"'), isFalse);
      expect(strictOpenAiReasoning(normalized), '用户想了解天气');
      expect(strictOpenAiContent(normalized), '北京晴。');
    });
  });

  group('normalizeChatSseText — tool_calls', () {
    test('strips empty-string id / name on Bailian continuation chunks', () {
      const sse =
          'data:{"choices":[{"delta":{"content":null,"reasoning_content":null,"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":""}}]},"index":0}]}\n\n'
          'data:{"choices":[{"delta":{"content":null,"reasoning_content":null,"tool_calls":[{"index":0,"id":"","type":"function","function":{"name":"","arguments":"{\\"city\\": \\"北京\\"}"}}]},"index":0}]}\n\n'
          'data:[DONE]\n\n';
      final normalized = normalizeChatSseText(sse);

      // Reconstruct the tool call the way a strict accumulator would.
      String? id;
      String? name;
      final args = StringBuffer();
      for (final line in normalized.split('\n')) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload == '[DONE]') continue;
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final delta = ((json['choices'] as List).first
            as Map<String, dynamic>)['delta'] as Map<String, dynamic>;
        final tcs = delta['tool_calls'];
        if (tcs is! List) continue;
        final tc = tcs.first as Map<String, dynamic>;
        if (tc.containsKey('id')) id = tc['id'] as String?;
        final fn = tc['function'] as Map<String, dynamic>;
        if (fn.containsKey('name')) name = fn['name'] as String?;
        args.write(fn['arguments'] as String? ?? '');
      }

      expect(id, 'call_abc');
      expect(name, 'get_weather');
      expect(args.toString(), '{"city": "北京"}');

      // The continuation chunk must NOT re-send id / name.
      final secondChunk = normalized.split('\n\n')[1];
      expect(secondChunk.contains('"id":""'), isFalse);
      expect(secondChunk.contains('"name":""'), isFalse);
    });
  });

  group('normalizeChatSseStream — chunk boundaries', () {
    test('handles a multibyte char split across two network chunks', () async {
      const event =
          'data:{"choices":[{"delta":{"content":"你好世界"},"index":0}]}\n\n';
      final bytes = utf8.encode(event);
      // Split at an odd byte offset that lands inside a multibyte char.
      final first = bytes.sublist(0, 30);
      final second = bytes.sublist(30);

      final source = Stream<List<int>>.fromIterable([first, second]);
      final collected = <int>[];
      await for (final out in normalizeChatSseStream(source)) {
        collected.addAll(out);
      }
      final normalized = utf8.decode(collected);
      expect(strictOpenAiContent(normalized), '你好世界');
    });

    test('buffers an incomplete event until its boundary arrives', () async {
      const event =
          'data:{"choices":[{"delta":{"content":"hi"},"index":0}]}\n\n';
      final bytes = utf8.encode(event);
      // Emit one byte at a time — worst case for the boundary detector.
      final source = Stream<List<int>>.fromIterable(
        bytes.map((b) => <int>[b]),
      );
      final collected = <int>[];
      await for (final out in normalizeChatSseStream(source)) {
        collected.addAll(out);
      }
      expect(strictOpenAiContent(utf8.decode(collected)), 'hi');
    });
  });
}
