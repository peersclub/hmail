import '../../domain/models.dart';

class AiResult {
  final DailyBrief? brief;
  final List<AttentionItem> attention;
  const AiResult({this.brief, this.attention = const []});

  static const empty = AiResult();
}

/// Optional intelligence layer. Implementations must never throw — a failed
/// AI call degrades to the rule-based brief, not a failed sync.
abstract interface class InsightAi {
  bool get isConfigured;
  String get label;

  Future<AiResult> analyze({
    required InsightSnapshot extracted,
    required List<EmailMeta> unclaimed,
  });
}

class NoAi implements InsightAi {
  const NoAi();

  @override
  bool get isConfigured => false;

  @override
  String get label => 'off';

  @override
  Future<AiResult> analyze({
    required InsightSnapshot extracted,
    required List<EmailMeta> unclaimed,
  }) async =>
      AiResult.empty;
}
