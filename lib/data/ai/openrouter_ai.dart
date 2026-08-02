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
    List<EmailMeta> sources = const [],
  }) async {
    final key = _apiKey;
    if (key == null) return AiResult.empty;

    final unclaimedBlock = unclaimed
        .take(30)
        .map((e) =>
            '- id=${e.id} | from=${e.from} | subject=${e.subject} | ${e.snippet}')
        .join('\n');

    // The audit needs each insight's originating email — a name or a
    // misclassification can only be judged against the real subject line.
    final sourceBlock = sources
        .take(60)
        .map((e) => '- id=${e.id} | from=${e.from} | subject=${e.subject}')
        .join('\n');

    final prompt = '''
You power the daily brief of an email-insights app. Rule-based parsers
extracted the structured data below from the user's Gmail. The parsers favour
recall, so some entries are wrong or badly named — your first job is to clean
them up.

EXTRACTED INSIGHTS:
${jsonEncode(extracted.toJson())}

SOURCE EMAILS for those insights (match on sourceEmailId):
$sourceBlock

UNCLASSIFIED EMAILS:
$unclaimedBlock

Tasks:
1. AUDIT every extracted insight against its source email.
   - "reject": sourceEmailId of anything that is not genuinely what it claims
     to be. Reject dev-tool/SaaS notifications posing as parcels ("deploy
     shipped", a PR touching package.json), marketing posing as bills,
     order-status emails with no real amount, and duplicates of the same
     real-world thing.
   - "rename": sourceEmailId → correct human brand name, when the current
     name is a mangled domain fragment ("Nct" → "Flipkart", "Alerts" →
     "HDFC Bank") or a raw domain. Use the name a person would say. Only
     include entries you are actually changing.
2. Write a 1-sentence headline and up to 4 short bullets for "Today" — only
   genuinely useful, forward-looking facts (due dates, renewals, arrivals,
   deadlines), and only about insights you did NOT reject. No filler, no
   restating counts.
3. From UNCLASSIFIED only, pick at most 5 emails a busy person must not miss
   (deadlines, security alerts, personal requests). Ignore marketing.

Return ONLY JSON:
{"reject": ["emailId"], "rename": {"emailId": "Brand Name"},
 "headline": "...", "bullets": ["..."],
 "attention": [{"id": "...", "title": "...", "reason": "..."}]}
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
        verdicts: InsightVerdicts(
          rejected: {
            for (final id in (json['reject'] ?? []) as List)
              if (id is String && id.isNotEmpty) id,
          },
          renamed: {
            for (final entry
                in ((json['rename'] ?? {}) as Map<String, dynamic>).entries)
              if (entry.value is String &&
                  (entry.value as String).trim().isNotEmpty)
                entry.key: (entry.value as String).trim(),
          },
        ),
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
