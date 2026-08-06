/// "What is this, actually?" — an AI summary of one email, on demand.
///
/// Rows are deliberately terse: a name, a figure, a date. That is right for a
/// glance and wrong for the moment a row is confusing, and some rows are
/// unavoidably confusing — mail from a payment intermediary, a learned recipe
/// whose label the app invented, an issuer whose brand nobody recognises. This
/// is the escape hatch for those: press and hold a row, and the model reads the
/// actual message and says what it is in two or three sentences.
///
/// ## Why on demand rather than during sync
///
/// Summarising every insight during a sync would multiply the AI bill by the
/// number of insights, and almost every summary would go unread — the whole
/// point of the app is that a glance is usually enough. Explaining one row costs
/// a fraction of a cent, only when a user actually asks, and the answer is
/// cached for the session so asking twice is free.
///
/// ## Never-throw contract
///
/// Like every AI surface here: nothing throws. A missing key, no network, a
/// deleted message or a malformed response all come back as an
/// [InsightExplanation] with a reason the user can act on. A sheet that explains
/// a row must not be the thing that crashes while explaining it.
library;

import 'package:dio/dio.dart';

import '../../core/ai_key.dart';
import '../mail/message_reader.dart';

/// The outcome of one explain request.
class InsightExplanation {
  /// The summary, when there is one.
  final String? text;

  /// Why there is no summary, phrased for a person rather than a log.
  final String? error;

  const InsightExplanation.ok(String this.text) : error = null;
  const InsightExplanation.failed(String this.error) : text = null;

  bool get ok => text != null;
}

/// Summarises a single message.
///
/// Reads through [MessageReader], so it shares that class's cache and its
/// `a<N>:` account-prefix handling, and inherits the rule that a body is
/// fetched fresh rather than stored.
class InsightExplainer {
  final Dio _dio;
  final MessageReader _reader;

  InsightExplainer({Dio? dio, MessageReader? reader})
      : _dio = dio ?? Dio(),
        _reader = reader ?? messageReader;

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  /// Summaries already produced this session, keyed by source email id.
  ///
  /// Unbounded only in the sense that it holds a few hundred bytes per entry
  /// against a user's manual presses — there is no realistic way to grow it
  /// large, and re-asking the model for an answer we have is pure waste.
  final _cache = <String, String>{};

  /// Whether explaining is possible at all: a key, and a backend to read the
  /// message from. False in demo mode and before sign-in, which is why the UI
  /// asks before offering the gesture.
  bool get isAvailable => AiKey.value != null && _reader.isAvailable;

  /// A cached summary, if this row has already been explained.
  String? cached(String sourceEmailId) => _cache[sourceEmailId];

  /// Explains [sourceEmailId]. [label] and [context] are what the app currently
  /// believes, passed in so the model can correct it rather than repeat it.
  Future<InsightExplanation> explain({
    required String sourceEmailId,
    required String label,
    String? context,
    String model = 'anthropic/claude-haiku-4.5',
  }) async {
    final hit = _cache[sourceEmailId];
    if (hit != null) return InsightExplanation.ok(hit);

    final key = AiKey.value;
    if (key == null) {
      return const InsightExplanation.failed(
          'Add an OpenRouter key in Settings → AI to explain a row.');
    }

    final body = await _reader.fetch(sourceEmailId);
    if (body == null) {
      return const InsightExplanation.failed(
          "Couldn't load the original email.");
    }

    // Strip tags rather than send markup: the model gains nothing from a
    // table layout, and HTML is most of the payload in a commercial email.
    final text = _plainText(body.html);

    final prompt = '''
Explain this email to its recipient in 2–3 short sentences.

The app currently labels it "$label"${context == null ? '' : ' ($context)'}.
If that label is wrong or misleading — a payment processor named instead of the
real biller, a brand nobody would recognise — say what it actually is first.

Cover, only where the email says so: who really sent it and on whose behalf,
what is being asked of the reader, how much money and by when, and anything that
looks like a deadline or a risk. If it is routine and needs nothing, say that
plainly — "nothing to do" is a useful answer.

Do not speculate beyond the email. Do not add a greeting, a sign-off, bullet
points or markdown. Plain sentences.

From: ${body.from}
Subject: ${body.subject}

$text
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
          'model': model,
          // Enough for three sentences and no more: the cap is what keeps this
          // a summary rather than a re-reading of the email.
          'max_tokens': 220,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        },
      );

      final choices =
          response.data is Map ? (response.data as Map)['choices'] : null;
      if (choices is! List || choices.isEmpty) {
        return const InsightExplanation.failed(
            'The AI response came back in a shape NoMail could not read.');
      }
      final content = ((choices.first as Map)['message'] as Map)['content'];
      final summary = content is String ? content.trim() : '';
      if (summary.isEmpty) {
        return const InsightExplanation.failed('The AI returned nothing.');
      }

      _cache[sourceEmailId] = summary;
      return InsightExplanation.ok(summary);
    } on DioException catch (e) {
      return InsightExplanation.failed(_describe(e));
    } catch (_) {
      return const InsightExplanation.failed(
          'Something went wrong asking the AI.');
    }
  }

  /// Body text worth sending: tags dropped, entities decoded, whitespace
  /// collapsed, and truncated — the recognisable substance of a commercial
  /// email is at the top, and the rest is footer and legal boilerplate.
  static String _plainText(String html) {
    var text = html
        .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>',
            caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|tr|h[1-6])>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n').trim();
    const limit = 4000;
    return text.length > limit ? text.substring(0, limit) : text;
  }

  static String _describe(DioException e) {
    final status = e.response?.statusCode;
    return switch (status) {
      401 || 403 => 'That OpenRouter key was rejected.',
      429 => 'Rate limited by OpenRouter — try again shortly.',
      _ when status != null && status >= 500 =>
        'OpenRouter is having trouble right now.',
      _ => 'No network, or OpenRouter did not answer.',
    };
  }
}

/// Shared instance, bound the same way as [messageReader] — a leaf row can ask
/// for an explanation without a controller threaded to it.
final InsightExplainer insightExplainer = InsightExplainer();
