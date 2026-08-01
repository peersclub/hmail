import '../../domain/brief_builder.dart';
import '../../domain/models.dart';
import '../ai/insight_ai.dart';
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

  Future<InsightSnapshot> run({InsightSnapshot? previous}) async {
    final emails = await source.fetchCandidates();
    final extracted = runExtractors(emails);

    var snapshot = InsightSnapshot(
      subscriptions: extracted.subscriptions,
      bills: extracted.bills,
      deliveries: extracted.deliveries,
      events: extracted.events,
      lastSyncedAt: DateTime.now(),
      emailsScanned: emails.length,
    );
    snapshot = store.merge(previous, snapshot);

    // Attention: heuristic floor, AI ceiling.
    final heuristicAttention = extractAttention(extracted.unclaimed);
    final aiResult = await ai.analyze(
      extracted: snapshot,
      unclaimed: extracted.unclaimed,
    );
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
