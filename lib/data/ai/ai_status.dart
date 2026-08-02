/// Live, honest reporting on the AI connection for the Settings screen.
///
/// Answers four questions a paying user of a privacy-sensitive app is entitled
/// to ask: is a key configured, does it actually work right now, which model is
/// it talking to, and how much has it cost. Cost transparency is the point —
/// the user's key is theirs, so what it spends is theirs to see.
///
/// ## Never-throw contract
///
/// Every method here follows the same rule as [InsightAi]: **nothing throws.**
/// [AiStatusService.fetchUsage] returns null on any failure and
/// [AiStatusService.testConnection] returns `ok: false` with a human-readable
/// reason. Callers never need a try/catch.
///
/// The reason is specific to this screen: Settings is where a user goes *when
/// something is already wrong*. An expired key, no network, a rate limit, or a
/// malformed response are all expected states here, not exceptional ones. If a
/// failed usage lookup could throw, the one screen capable of explaining the
/// problem would be the screen that crashes. So the connection panel degrades
/// to "unknown" and stays readable instead.
///
/// Configure in .env (shared with [OpenRouterAi]):
///   OPENROUTER_API_KEY=sk-or-...
///   OPENROUTER_MODEL=anthropic/claude-haiku-4.5   (optional override)
library;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Spend on the configured OpenRouter key, as reported by `GET /api/v1/key`.
class AiKeyUsage {
  /// All-time spend in US dollars.
  final double usage;

  /// Spend in the current UTC day.
  final double usageDaily;

  /// Spend in the current UTC month.
  final double usageMonthly;

  /// Credit limit in dollars, or null when no spend cap is set on the key.
  final double? limit;

  /// Remaining credit in dollars, or null when there is no cap.
  final double? limitRemaining;

  /// Whether the key is on OpenRouter's free tier.
  final bool isFreeTier;

  /// The key's human label, as named in the OpenRouter dashboard.
  final String label;

  const AiKeyUsage({
    required this.usage,
    required this.usageDaily,
    required this.usageMonthly,
    required this.limit,
    required this.limitRemaining,
    required this.isFreeTier,
    required this.label,
  });

  /// Whether a spend cap is configured on this key.
  bool get hasSpendCap => limit != null;

  /// One line of spend, phrased for whichever number is actually meaningful.
  ///
  /// With a cap, all-time spend against the cap is the number that matters
  /// ("how close am I to being cut off"). Without one there is nothing to
  /// measure against, so the monthly figure is the useful proxy for burn rate.
  String get spendSummary {
    final cap = limit;
    if (cap == null) return '${_money(usageMonthly)} this month';
    return '${_money(usage)} of ${_money(cap)} used';
  }

  /// A short caution when the key has no ceiling on what it can spend, else
  /// null. An uncapped key is the single most expensive misconfiguration a
  /// user can leave in place, so the Settings screen says so plainly.
  String? get warning =>
      hasSpendCap ? null : 'No spend limit set on this key';

  static String _money(double amount) => '\$${amount.toStringAsFixed(2)}';

  /// Parses the `data` object of `GET /api/v1/key`. Missing or oddly-typed
  /// fields degrade to zero / null rather than throwing — a usage panel that
  /// under-reports is better than one that takes down Settings.
  static AiKeyUsage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final data = raw['data'] is Map ? raw['data'] as Map : raw;
    // A payload with none of the usage fields is not a key response at all.
    if (!data.containsKey('usage') && !data.containsKey('label')) return null;
    return AiKeyUsage(
      usage: _num(data['usage']) ?? 0,
      usageDaily: _num(data['usage_daily']) ?? 0,
      usageMonthly: _num(data['usage_monthly']) ?? 0,
      limit: _num(data['limit']),
      limitRemaining: _num(data['limit_remaining']),
      isFreeTier: data['is_free_tier'] == true,
      label: data['label'] is String ? data['label'] as String : '',
    );
  }

  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// Outcome of a live round-trip against the chat completions endpoint.
class AiConnectionResult {
  /// Whether the request came back with a usable completion.
  final bool ok;

  /// Measured wall-clock time of the request, when one was made.
  final Duration? latency;

  /// The model the request was sent to.
  final String? model;

  /// A short human-readable reason, set only when [ok] is false.
  final String? error;

  const AiConnectionResult({
    required this.ok,
    this.latency,
    this.model,
    this.error,
  });

  /// One line fit for display next to a status dot.
  String get summary {
    if (!ok) return error ?? 'Not connected';
    final ms = latency?.inMilliseconds;
    return ms == null ? 'Connected' : 'Connected · $ms ms';
  }
}

/// One entry in the curated model picker.
class AiModelOption {
  /// The OpenRouter model slug to send as `model`.
  final String slug;

  /// Short human label for the picker row.
  final String label;

  /// One line on what you give up or gain by choosing it.
  final String note;

  const AiModelOption({
    required this.slug,
    required this.label,
    required this.note,
  });
}

/// Reads the AI configuration and probes it, for display in Settings.
///
/// Never throws — see the library doc comment.
class AiStatusService {
  final Dio _dio;

  AiStatusService({Dio? dio}) : _dio = dio ?? Dio();

  static const _keyEndpoint = 'https://openrouter.ai/api/v1/key';
  static const _chatEndpoint = 'https://openrouter.ai/api/v1/chat/completions';

  /// Kept in sync with [OpenRouterAi] so Settings never reports a different
  /// model than the one actually used for analysis.
  static const _defaultModel = 'anthropic/claude-haiku-4.5';

  /// A small, honest catalog. Not every model OpenRouter carries — the three
  /// or four worth offering for daily-brief work, with the trade-off stated so
  /// the choice is informed rather than a wall of slugs. A non-Anthropic entry
  /// is included deliberately: a picker that only lists one vendor is a
  /// recommendation pretending to be a choice.
  static const modelOptions = <AiModelOption>[
    AiModelOption(
      slug: 'anthropic/claude-haiku-4.5',
      label: 'Claude Haiku 4.5',
      note: 'Recommended. Cheapest Claude here and quick — the brief and the '
          'audit are classification work, which it handles well.',
    ),
    AiModelOption(
      slug: 'anthropic/claude-sonnet-5',
      label: 'Claude Sonnet 5',
      note: 'Sharper judgement on messy inboxes and better brand naming, at '
          'a few times the cost per sync.',
    ),
    AiModelOption(
      slug: 'anthropic/claude-opus-5',
      label: 'Claude Opus 5',
      note: 'Noticeably better judgement on messy inboxes, at roughly 2.5x '
          'the cost per sync.',
    ),
    AiModelOption(
      slug: 'anthropic/claude-fable-5',
      label: 'Claude Fable 5',
      note: 'Frontier reasoning. Overkill for a daily brief and the most '
          'expensive option — pick it only if the others miss things.',
    ),
    AiModelOption(
      slug: 'google/gemini-3.6-flash',
      label: 'Gemini 3.6 Flash',
      note: 'Cheapest and quickest here. Good for high email volume; weaker '
          'at spotting a mislabelled insight.',
    ),
  ];

  /// The raw key, or null when unset or blank. Never leaves this class.
  String? get _apiKey {
    final key = _env('OPENROUTER_API_KEY')?.trim();
    return (key == null || key.isEmpty) ? null : key;
  }

  /// Whether a key is present at all.
  bool get isConfigured => _apiKey != null;

  /// The key with its middle removed — e.g. `sk-or-…65d9`. Enough for a user
  /// to confirm *which* key is configured, useless to anyone who reads it off
  /// a screenshot. Null when unconfigured.
  String? get maskedKey {
    final key = _apiKey;
    if (key == null) return null;
    if (key.length <= 10) {
      // Too short to show a prefix without giving away most of it.
      final tail = key.length <= 4 ? key : key.substring(key.length - 4);
      return '…$tail';
    }
    return '${key.substring(0, 6)}…${key.substring(key.length - 4)}';
  }

  /// The model in use, resolved exactly as [OpenRouterAi] resolves it.
  String get model {
    final override = _env('OPENROUTER_MODEL')?.trim();
    return (override == null || override.isEmpty) ? _defaultModel : override;
  }

  /// Current spend on the key, or null if it could not be determined.
  ///
  /// Returns null — never throws — on a missing key, network failure, error
  /// status, or unparseable body. Settings renders "unknown" for null.
  Future<AiKeyUsage?> fetchUsage() async {
    final key = _apiKey;
    if (key == null) return null;
    try {
      final response = await _dio.get(
        _keyEndpoint,
        options: Options(headers: _headers(key)),
      );
      return AiKeyUsage.fromJson(response.data);
    } catch (_) {
      return null;
    }
  }

  /// Sends the smallest possible real completion and times it.
  ///
  /// Deliberately tiny — one short message, `max_tokens: 5` — because this runs
  /// whenever a user taps "Test connection" and should cost a fraction of a
  /// cent. A configured-but-broken key is the failure this exists to catch, so
  /// it verifies end to end rather than just checking the key is non-empty.
  ///
  /// Never throws: failures come back as `ok: false` with a reason a
  /// non-technical user can act on.
  Future<AiConnectionResult> testConnection() async {
    final key = _apiKey;
    if (key == null) {
      return const AiConnectionResult(
        ok: false,
        error: 'No API key set — add OPENROUTER_API_KEY',
      );
    }

    final target = model;
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.post(
        _chatEndpoint,
        options: Options(headers: _headers(key)),
        data: {
          'model': target,
          'max_tokens': 5,
          'messages': [
            {'role': 'user', 'content': 'Reply with OK.'}
          ],
        },
      );
      stopwatch.stop();

      final choices = (response.data is Map)
          ? (response.data as Map)['choices']
          : null;
      if (choices is! List || choices.isEmpty) {
        return AiConnectionResult(
          ok: false,
          latency: stopwatch.elapsed,
          model: target,
          error: 'Unexpected response from OpenRouter',
        );
      }

      return AiConnectionResult(
        ok: true,
        latency: stopwatch.elapsed,
        model: target,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      return AiConnectionResult(
        ok: false,
        latency: stopwatch.elapsed,
        model: target,
        error: _describe(e),
      );
    } catch (_) {
      stopwatch.stop();
      return AiConnectionResult(
        ok: false,
        latency: stopwatch.elapsed,
        model: target,
        error: 'Request failed',
      );
    }
  }

  Map<String, String> _headers(String key) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
        'HTTP-Referer': 'https://github.com/peersclub/hmail',
        'X-Title': 'NoMail',
      };

  /// Turns a transport failure into something worth showing a user. Each
  /// message names the thing they can actually change.
  static String _describe(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return 'No network';
      default:
        break;
    }
    if (e.error is Exception &&
        e.error.toString().toLowerCase().contains('socket')) {
      return 'No network';
    }

    final code = e.response?.statusCode;
    switch (code) {
      case 401:
        return 'Key rejected — check OPENROUTER_API_KEY';
      case 402:
        return 'Out of credits';
      case 429:
        return 'Rate limited, try again shortly';
      case null:
        return 'Request failed';
      default:
        return 'Request failed ($code)';
    }
  }

  /// dotenv throws if `load()` was never called (a fresh install with no .env
  /// asset, or a widget test). Reading config must not be able to break
  /// Settings, so a missing environment reads as "unconfigured".
  static String? _env(String name) {
    try {
      return dotenv.maybeGet(name);
    } catch (_) {
      return null;
    }
  }
}
