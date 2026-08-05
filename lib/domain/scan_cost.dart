/// "About 200 emails, roughly 2¢" — what a scan will cost before it runs.
///
/// The app spends the user's own OpenRouter key, so it owes them a number
/// beforehand, not just a receipt afterwards. Settings already shows spend to
/// date; this is the other half.
///
/// The estimate is honest for one specific reason: both AI calls in a sync are
/// **hard-capped**, so its upper bound is a real ceiling rather than a guess.
/// `OpenRouterAi.analyze` sends at most 60 source lines and 30 unclassified
/// lines plus the extracted-snapshot JSON, with `max_tokens: 1500`;
/// `KnowledgeLearner` sends at most 5 clusters × 3 samples with
/// `max_tokens: 2000`. Changing those caps changes the constants here, and the
/// tests assert they stay in step.
///
/// Prices are not hardcoded — they come from OpenRouter's own models endpoint.
/// A stale price table on a screen whose entire job is being trustworthy would
/// be worse than showing nothing, so when pricing can't be fetched the estimate
/// reports the email count and no money at all.
library;

import 'scan_settings.dart';

/// Per-token USD prices for one model, as OpenRouter reports them.
class ModelPricing {
  final double promptUsdPerToken;
  final double completionUsdPerToken;

  const ModelPricing({
    required this.promptUsdPerToken,
    required this.completionUsdPerToken,
  });

  /// True when both numbers are usable. A model priced at zero is either free
  /// (nothing to warn about) or a parse failure — either way there is no
  /// estimate worth showing.
  bool get isPriced => promptUsdPerToken > 0 || completionUsdPerToken > 0;

  /// Parses OpenRouter's `pricing` object, whose values are USD-per-token
  /// **as strings** ("0.000001"). Null on anything unexpected: a
  /// misparsed price would put a wrong number on a trust surface.
  static ModelPricing? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final prompt = _rate(raw['prompt']);
    final completion = _rate(raw['completion']);
    if (prompt == null || completion == null) return null;
    return ModelPricing(
      promptUsdPerToken: prompt,
      completionUsdPerToken: completion,
    );
  }

  static double? _rate(Object? value) {
    final parsed = switch (value) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };
    // Negative is nonsense; -1 is how OpenRouter marks "priced elsewhere".
    return (parsed == null || parsed < 0) ? null : parsed;
  }
}

/// Prompt-side caps, mirroring the request builders they describe.
const _auditSourceLines = 60;
const _auditUnclaimedLines = 30;
const _auditMaxOutputTokens = 1500;
const _learnerMaxOutputTokens = 2000;
const _learnerClusters = 5;
const _learnerSamples = 3;

/// Roughly four characters per token, the usual English ratio.
///
/// A source line is `- id=… | from=… | subject=…` (~120 chars); an unclassified
/// line adds the snippet (~200 chars); one insight's JSON runs ~240 chars.
const _tokensPerSourceLine = 30;
const _tokensPerUnclaimedLine = 50;
const _tokensPerInsightJson = 60;

/// The fixed instruction text in each prompt.
const _auditOverheadTokens = 750;
const _learnerOverheadTokens = 900;

/// Share of scanned emails that typically become insights. Used only to size
/// the snapshot JSON, and deliberately generous — over-estimating cost is the
/// safe direction to be wrong in.
const _insightYield = 0.6;

class ScanCostEstimate {
  /// Upper bound on emails read, from [ScanSettings.estimatedMaxEmails].
  final int emails;

  /// USD range for one full scan, or null when pricing was unavailable.
  final double? lowUsd;
  final double? highUsd;

  const ScanCostEstimate({
    required this.emails,
    this.lowUsd,
    this.highUsd,
  });

  bool get hasPrice => lowUsd != null && highUsd != null;

  /// Just the money, or null when there is no price to state.
  ///
  /// Phrased as a range because token counts vary with how chatty the inbox is,
  /// and the top of the range is a genuine ceiling rather than a hope — the
  /// prompt caps guarantee it. Sub-cent totals read as "under a cent": a
  /// "$0.00" estimate looks like a bug, not like cheap.
  String? get priceLine {
    if (!hasPrice) return null;
    if (highUsd! < 0.01) return 'Under a cent of AI per scan';
    return 'About ${_money(lowUsd!)}–${_money(highUsd!)} of AI per scan';
  }

  /// Scope and cost in one line, for a settings row subtitle.
  String get summary {
    final scope = 'Up to $emails email${emails == 1 ? '' : 's'} per scan';
    final price = priceLine;
    if (price == null) return '$scope · AI cost unknown';
    return '$scope · ${price[0].toLowerCase()}${price.substring(1)}';
  }

  static String _money(double usd) =>
      usd < 0.01 ? '<\$0.01' : '\$${usd.toStringAsFixed(2)}';
}

/// Estimates one full scan under [settings].
///
/// [pricing] null (or unpriced) yields a count-only estimate — see the library
/// note on why a fabricated price would be worse than no price.
///
/// The low end assumes the audit runs alone with a typical-length answer; the
/// high end assumes both calls run against full prompts and hit their output
/// ceilings. `learnerRuns` false drops the second call from both ends, which is
/// what happens when nothing went unrecognised.
ScanCostEstimate estimateScanCost({
  required ScanSettings settings,
  ModelPricing? pricing,
  bool learnerRuns = true,
}) {
  final emails = settings.estimatedMaxEmails;
  if (pricing == null || !pricing.isPriced || emails == 0) {
    return ScanCostEstimate(emails: emails);
  }

  final aiOn = settings.aiEnabled;
  if (!aiOn) return ScanCostEstimate(emails: emails, lowUsd: 0, highUsd: 0);

  // Audit prompt: instructions + snapshot JSON + the two capped line blocks.
  final insights = (emails * _insightYield).round();
  final auditPromptTokens = _auditOverheadTokens +
      insights * _tokensPerInsightJson +
      _min(emails, _auditSourceLines) * _tokensPerSourceLine +
      _min(emails, _auditUnclaimedLines) * _tokensPerUnclaimedLine;

  final learnerPromptTokens = learnerRuns
      ? _learnerOverheadTokens +
          _learnerClusters * _learnerSamples * _tokensPerUnclaimedLine
      : 0;

  double cost(int promptTokens, int outputTokens) =>
      promptTokens * pricing.promptUsdPerToken +
      outputTokens * pricing.completionUsdPerToken;

  // A typical answer is a fraction of the ceiling: the audit writes a headline,
  // four bullets and a short verdict list, not 1500 tokens of it.
  final low = cost(auditPromptTokens, (_auditMaxOutputTokens * 0.3).round());
  final high = cost(auditPromptTokens, _auditMaxOutputTokens) +
      cost(learnerPromptTokens, learnerRuns ? _learnerMaxOutputTokens : 0);

  return ScanCostEstimate(emails: emails, lowUsd: low, highUsd: high);
}

int _min(int a, int b) => a < b ? a : b;
