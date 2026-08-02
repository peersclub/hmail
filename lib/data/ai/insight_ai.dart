import '../../domain/models.dart';

/// AI judgement over what the rule extractors produced.
///
/// Rules are tuned for recall and occasionally claim the wrong thing (a
/// GitHub deploy notice reading as a parcel) or name it badly ("Nct" from
/// nct.flipkart.com). The model sees every extracted insight next to its
/// source email and votes: drop it, or rename it. Keyed by
/// `sourceEmailId` — the one identifier that survives extraction.
class InsightVerdicts {
  /// Insights the model judged not real; removed from the snapshot.
  final Set<String> rejected;

  /// Better display names: sourceEmailId → merchant/issuer/service.
  final Map<String, String> renamed;

  const InsightVerdicts({
    this.rejected = const {},
    this.renamed = const {},
  });

  static const empty = InsightVerdicts();

  bool get isEmpty => rejected.isEmpty && renamed.isEmpty;
}

class AiResult {
  final DailyBrief? brief;
  final List<AttentionItem> attention;
  final InsightVerdicts verdicts;

  const AiResult({
    this.brief,
    this.attention = const [],
    this.verdicts = InsightVerdicts.empty,
  });

  static const empty = AiResult();
}

/// Optional intelligence layer. Implementations must never throw — a failed
/// AI call degrades to the rule-based brief, not a failed sync.
abstract interface class InsightAi {
  bool get isConfigured;
  String get label;

  /// [sources] are the emails the extracted insights came from — the audit
  /// can only judge a misclassification against its original subject line.
  Future<AiResult> analyze({
    required InsightSnapshot extracted,
    required List<EmailMeta> unclaimed,
    List<EmailMeta> sources = const [],
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
    List<EmailMeta> sources = const [],
  }) async =>
      AiResult.empty;
}
