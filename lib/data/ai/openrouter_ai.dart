import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../domain/models.dart';
import 'insight_ai.dart';

/// AI gateway via OpenRouter (OpenAI-compatible chat completions API).
///
/// Configure in .env:
///   OPENROUTER_API_KEY=sk-or-...
///   OPENROUTER_MODEL=anthropic/claude-haiku-4.5   (optional override)
class OpenRouterAi implements InsightAi {
  final Dio _dio;

  OpenRouterAi({Dio? dio}) : _dio = dio ?? Dio();

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const _defaultModel = 'anthropic/claude-haiku-4.5';

  String? get _apiKey {
    final key = dotenv.maybeGet('OPENROUTER_API_KEY')?.trim();
    return (key == null || key.isEmpty) ? null : key;
  }

  String get _model =>
      dotenv.maybeGet('OPENROUTER_MODEL')?.trim().isNotEmpty == true
          ? dotenv.maybeGet('OPENROUTER_MODEL')!.trim()
          : _defaultModel;

  @override
  bool get isConfigured => _apiKey != null;

  @override
  String get label => isConfigured ? 'OpenRouter · $_model' : 'off';

  @override
  Future<AiResult> analyze({
    required InsightSnapshot extracted,
    required List<EmailMeta> unclaimed,
  }) async {
    final key = _apiKey;
    if (key == null) return AiResult.empty;

    final unclaimedBlock = unclaimed
        .take(30)
        .map((e) =>
            '- id=${e.id} | from=${e.from} | subject=${e.subject} | ${e.snippet}')
        .join('\n');

    final prompt = '''
You power the daily brief of an email-insights app. Below is structured data
extracted from the user's Gmail, plus unclassified recent emails.

EXTRACTED (already shown in dashboards — do not repeat verbatim):
${jsonEncode(extracted.toJson())}

UNCLASSIFIED EMAILS:
$unclaimedBlock

Tasks:
1. Write a 1-sentence headline and up to 4 short bullets for "Today" — only
   genuinely useful, forward-looking facts (due dates, renewals, arrivals,
   deadlines). No filler, no restating counts.
2. From UNCLASSIFIED only, pick at most 5 emails a busy person must not miss
   (deadlines, security alerts, personal requests). Ignore marketing.

Return ONLY JSON:
{"headline": "...", "bullets": ["..."], "attention": [{"id": "...", "title": "...", "reason": "..."}]}
''';

    try {
      final response = await _dio.post(
        _endpoint,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
          'HTTP-Referer': 'https://github.com/peersclub/hmail',
          'X-Title': 'NoMail',
        }),
        data: {
          'model': _model,
          'max_tokens': 1500,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        },
      );

      final content = (((response.data['choices'] as List).first
              as Map<String, dynamic>)['message']
          as Map<String, dynamic>)['content'] as String;
      final json = jsonDecode(_stripFences(content)) as Map<String, dynamic>;

      final byId = {for (final e in unclaimed) e.id: e};
      final attention = <AttentionItem>[
        for (final raw in (json['attention'] ?? []) as List)
          AttentionItem(
            title: ((raw as Map<String, dynamic>)['title'] ?? '') as String,
            reason: (raw['reason'] ?? '') as String,
            date: byId[raw['id']]?.date ?? DateTime.now(),
            sourceEmailId: (raw['id'] ?? '') as String,
          ),
      ];

      return AiResult(
        brief: DailyBrief(
          headline: (json['headline'] ?? '') as String,
          bullets: ((json['bullets'] ?? []) as List).cast<String>(),
          generatedAt: DateTime.now(),
        ),
        attention: attention,
      );
    } catch (_) {
      return AiResult.empty;
    }
  }

  String _stripFences(String text) {
    var out = text.trim();
    if (out.startsWith('```')) {
      out = out.replaceFirst(RegExp(r'^```[a-z]*\s*'), '');
      if (out.endsWith('```')) out = out.substring(0, out.length - 3);
    }
    return out.trim();
  }
}
