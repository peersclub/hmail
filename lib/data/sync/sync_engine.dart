import '../../domain/brief_builder.dart';
import '../../domain/knowledge.dart';
import '../../domain/knowledge_mapper.dart';
import '../../domain/models.dart';
import '../../domain/scan_settings.dart';
import '../../domain/sync_report.dart';
import '../ai/insight_ai.dart';
import '../ai/knowledge_learner.dart';
import '../extractors/extractors.dart';
import '../mail/mail_source.dart';
import '../store/insight_store.dart';

/// The one use-case in the app: mail → extraction → (optional AI) → snapshot.
///
/// Pure orchestration with injected dependencies; the controller stays thin
/// and the whole pipeline is testable with fakes.
class SyncEngine {
  final MailSource source;
  final InsightAi ai;
  final InsightStore store;

  const SyncEngine({
    required this.source,
    required this.ai,
    required this.store,
  });

  /// Runs the pipeline, reporting progress through [onStage] so Settings can
  /// show what the app is doing while it does it, and returning a
  /// [SyncReport] describing what happened — including what the AI changed.
  Future<({InsightSnapshot snapshot, SyncReport report, Playbook playbook})>
      runReported({
    InsightSnapshot? previous,
    ScanSettings settings = const ScanSettings(),
    Playbook playbook = Playbook.empty,
    KnowledgeLearner? learner,
    void Function(SyncStage stage)? onStage,
  }) async {
    final startedAt = DateTime.now();
    final clock = Stopwatch()..start();

    onStage?.call(SyncStage.fetching);
    final emails = await source.fetchCandidates();

    onStage?.call(SyncStage.extracting);
    final extracted = runExtractors(emails);

    // Learned knowledge runs on whatever the hand-written rules didn't claim.
    // This is pure application of stored recipes — no model, no network.
    final knowledgeMatches = <(EmailMeta, KnowledgeMatch)>[];
    final stillUnclaimed = <EmailMeta>[];
    for (final email in extracted.unclaimed) {
      final match = playbook.apply(email);
      if (match == null) {
        stillUnclaimed.add(email);
      } else {
        knowledgeMatches.add((email, match));
      }
    }
    final learned = mapKnowledge(knowledgeMatches);

    var snapshot = InsightSnapshot(
      subscriptions: [...extracted.subscriptions, ...learned.subscriptions],
      bills: [...extracted.bills, ...learned.bills],
      deliveries: [...extracted.deliveries, ...learned.deliveries],
      events: [...extracted.events, ...learned.events],
      travel: extracted.travel,
      payments: extracted.payments,
      returns: extracted.returns,
      feed: extracted.feed,
      lastSyncedAt: DateTime.now(),
      emailsScanned: emails.length,
    );
    snapshot = store.merge(previous, snapshot);

    var report = SyncReport(
      startedAt: startedAt,
      emailsFetched: emails.length,
      subscriptionsFound: extracted.subscriptions.length,
      billsFound: extracted.bills.length,
      deliveriesFound: extracted.deliveries.length,
      eventsFound: extracted.events.length,
      unclaimedCount: stillUnclaimed.length,
      knowledgeApplied: knowledgeMatches.length,
      stage: SyncStage.auditing,
    );

    // Learned attention items rank above the heuristic ones: a recipe the
    // user has kept is better evidence than a keyword guess.
    final heuristicAttention = [
      ...learned.attention,
      ...extractAttention(stillUnclaimed),
    ];

    if (settings.aiEnabled && ai.isConfigured) {
      onStage?.call(SyncStage.auditing);
      final preAudit = snapshot;
      final aiResult = await ai.analyze(
        extracted: snapshot,
        unclaimed: stillUnclaimed,
        sources: emails,
      );
      snapshot = applyVerdicts(snapshot, aiResult.verdicts);
      snapshot = snapshot.copyWith(
        attention: aiResult.attention.isNotEmpty
            ? aiResult.attention
            : heuristicAttention,
        brief: aiResult.brief ?? buildRuleBrief(snapshot),
      );
      report = report
          .copyWith(aiRan: true)
          .withAudit(AiAuditSummary.fromVerdicts(
            aiResult.verdicts,
            preAudit: preAudit,
          ));
    } else {
      // AI off (or unconfigured): rules carry the whole load, as designed.
      snapshot = snapshot.copyWith(
        attention: heuristicAttention,
        brief: buildRuleBrief(snapshot),
      );
    }

    // Teach: anything still unrecognised becomes a candidate for a new
    // recipe. Learning happens after the audit so it never delays the
    // brief, and its results only take effect from the next sync — this
    // sync's output was already decided.
    var nextPlaybook = playbook;
    if (settings.aiEnabled &&
        learner != null &&
        learner.isConfigured &&
        stillUnclaimed.isNotEmpty) {
      onStage?.call(SyncStage.learning);
      final result = await learner.learn(
        unclaimed: stillUnclaimed,
        known: playbook,
      );
      for (final type in result.types) {
        nextPlaybook = nextPlaybook.upsert(type);
      }
      report = report.copyWith(
        typesLearned: result.types.length,
        learnedLabels: [for (final type in result.types) type.label],
      );
    }

    onStage?.call(SyncStage.saving);
    await store.save(snapshot);

    clock.stop();
    onStage?.call(SyncStage.done);
    return (
      snapshot: snapshot,
      report: report.copyWith(duration: clock.elapsed, stage: SyncStage.done),
      playbook: nextPlaybook,
    );
  }

  Future<InsightSnapshot> run({InsightSnapshot? previous}) async {
    final emails = await source.fetchCandidates();
    final extracted = runExtractors(emails);

    var snapshot = InsightSnapshot(
      subscriptions: extracted.subscriptions,
      bills: extracted.bills,
      deliveries: extracted.deliveries,
      events: extracted.events,
      travel: extracted.travel,
      payments: extracted.payments,
      returns: extracted.returns,
      feed: extracted.feed,
      lastSyncedAt: DateTime.now(),
      emailsScanned: emails.length,
    );
    snapshot = store.merge(previous, snapshot);

    // Attention: heuristic floor, AI ceiling.
    final heuristicAttention = extractAttention(extracted.unclaimed);
    final aiResult = await ai.analyze(
      extracted: snapshot,
      unclaimed: extracted.unclaimed,
      sources: emails,
    );
    snapshot = applyVerdicts(snapshot, aiResult.verdicts);
    snapshot = snapshot.copyWith(
      attention: aiResult.attention.isNotEmpty
          ? aiResult.attention
          : heuristicAttention,
    );

    // Brief: rule-built always, AI-upgraded when available.
    snapshot = snapshot.copyWith(
      brief: aiResult.brief ?? buildRuleBrief(snapshot),
    );

    await store.save(snapshot);
    return snapshot;
  }
}

/// Applies the AI audit to a snapshot: drops rejected insights and adopts
/// better display names. Pure and separately testable — a bad verdict set
/// should never be able to corrupt the snapshot silently.
InsightSnapshot applyVerdicts(
  InsightSnapshot snapshot,
  InsightVerdicts verdicts,
) {
  if (verdicts.isEmpty) return snapshot;

  bool kept(String sourceEmailId) => !verdicts.rejected.contains(sourceEmailId);
  String? newName(String sourceEmailId) => verdicts.renamed[sourceEmailId];

  return snapshot.copyWith(
    subscriptions: [
      for (final s in snapshot.subscriptions)
        if (kept(s.sourceEmailId))
          switch (newName(s.sourceEmailId)) {
            final String name => s.withService(name),
            null => s,
          },
    ],
    bills: [
      for (final b in snapshot.bills)
        if (kept(b.sourceEmailId))
          switch (newName(b.sourceEmailId)) {
            final String name => b.withIssuer(name),
            null => b,
          },
    ],
    deliveries: [
      for (final d in snapshot.deliveries)
        if (kept(d.sourceEmailId))
          switch (newName(d.sourceEmailId)) {
            final String name => d.withMerchant(name),
            null => d,
          },
    ],
    events: [
      for (final e in snapshot.events)
        if (kept(e.sourceEmailId)) e,
    ],
    travel: [
      for (final t in snapshot.travel)
        if (kept(t.sourceEmailId)) t,
    ],
    payments: [
      for (final p in snapshot.payments)
        if (kept(p.sourceEmailId)) p,
    ],
    returns: [
      for (final r in snapshot.returns)
        if (kept(r.sourceEmailId)) r,
    ],
  );
}
