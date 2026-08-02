/// The receipt for one sync run: what NoMail read, what it found, and — the
/// part that actually matters — what the AI changed about the user's data.
///
/// People pay for this app partly to *not* be surprised by it. The Processing
/// screen in Settings renders this record verbatim, so an audit that silently
/// dropped a package or renamed a merchant is visible instead of spooky.
/// Pure Dart: no Flutter, no clock inside the math — the same report always
/// produces the same words.
library;

import '../data/ai/insight_ai.dart';
import 'models.dart';

/// Where a sync currently is. Ordered along the pipeline in
/// `SyncEngine.run` (fetch → extract → AI audit → save) so a progress
/// indicator can use `index / values.length` without a lookup table.
enum SyncStage { idle, fetching, extracting, auditing, learning, saving, done, failed }

extension SyncStageLabel on SyncStage {
  /// User-facing text. Deliberately plain-English: "AI checking results"
  /// tells someone what the model is doing to their mail, where "auditing"
  /// would not.
  String get label => switch (this) {
    SyncStage.idle => 'Not scanned yet',
    SyncStage.fetching => 'Reading mail',
    SyncStage.extracting => 'Finding insights',
    SyncStage.auditing => 'AI checking results',
    SyncStage.learning => 'Learning new types',
    SyncStage.saving => 'Saving',
    SyncStage.done => 'Up to date',
    SyncStage.failed => 'Failed',
  };

  /// True while work is in flight — for spinners and "don't sync again yet".
  bool get isBusy => switch (this) {
    SyncStage.fetching ||
    SyncStage.extracting ||
    SyncStage.auditing ||
    SyncStage.learning ||
    SyncStage.saving => true,
    _ => false,
  };
}

String _plural(int count, String singular, [String? plural]) =>
    count == 1 ? singular : (plural ?? '${singular}s');

/// What the AI audit did, in words a human can check.
///
/// Split out from [SyncReport] because it is the one piece with real logic:
/// [InsightVerdicts] is keyed by `sourceEmailId`, which is meaningless to a
/// user, so every note has to be resolved back to the *thing* it affected
/// ("Flipkart", not "fk-1").
class AiAuditSummary {
  /// Insights actually dropped — counted per insight, not per verdict, so a
  /// verdict matching nothing counts as nothing.
  final int rejected;

  /// Insights actually renamed. A rename to the name it already had is not a
  /// change and is not counted.
  final int renamed;

  /// Human-readable lines, in snapshot order: 'Dropped Github — not a real
  /// package', 'Renamed Nct → Flipkart'.
  final List<String> notes;

  const AiAuditSummary({
    this.rejected = 0,
    this.renamed = 0,
    this.notes = const [],
  });

  static const empty = AiAuditSummary();

  bool get isEmpty => rejected == 0 && renamed == 0;

  /// Describes [verdicts] against [preAudit] — the snapshot as it looked
  /// *before* [applyVerdicts] ran, the only place the affected names still
  /// exist.
  ///
  /// Walks the snapshot rather than the verdict set: that keeps note order
  /// stable (subscriptions, bills, deliveries, events) and makes an unknown
  /// id impossible to report, since a note can only come from an insight
  /// that was really there.
  factory AiAuditSummary.fromVerdicts(
    InsightVerdicts verdicts, {
    required InsightSnapshot preAudit,
  }) {
    if (verdicts.isEmpty) return AiAuditSummary.empty;

    final notes = <String>[];
    var rejected = 0;
    var renamed = 0;

    void consider(String sourceEmailId, String name, String kind) {
      if (verdicts.rejected.contains(sourceEmailId)) {
        rejected++;
        notes.add('Dropped $name — not a real $kind');
        return;
      }
      final better = verdicts.renamed[sourceEmailId];
      if (better != null && better != name) {
        renamed++;
        notes.add('Renamed $name → $better');
      }
    }

    for (final s in preAudit.subscriptions) {
      consider(s.sourceEmailId, s.service, 'subscription');
    }
    for (final b in preAudit.bills) {
      consider(b.sourceEmailId, b.issuer, 'bill');
    }
    for (final d in preAudit.deliveries) {
      consider(d.sourceEmailId, d.merchant, 'package');
    }
    for (final e in preAudit.events) {
      // Events are never renamed by the audit (see applyVerdicts) but can
      // still be rejected.
      consider(e.sourceEmailId, e.title, 'meeting');
    }

    return AiAuditSummary(
      rejected: rejected,
      renamed: renamed,
      notes: List.unmodifiable(notes),
    );
  }
}

/// One completed (or failed) sync, ready to show.
class SyncReport {
  final DateTime startedAt;
  final Duration duration;

  /// Emails handed to the extractors — the "we read N messages" number.
  final int emailsFetched;

  final int subscriptionsFound;
  final int billsFound;
  final int deliveriesFound;
  final int eventsFound;

  /// Emails no extractor claimed. Not an insight, so it stays out of
  /// [totalInsights] and [breakdown]; useful as a recall signal.
  final int unclaimedCount;

  /// Emails handled by a learned recipe rather than a hand-written rule —
  /// the number that should climb as the app is taught more.
  final int knowledgeApplied;

  /// New recipes written this sync, and their human labels.
  final int typesLearned;
  final List<String> learnedLabels;

  /// False when no AI is configured, or the key is missing — the app is fully
  /// usable without it and the report should say so rather than imply the
  /// model looked and found nothing.
  final bool aiRan;

  final int aiRejected;
  final int aiRenamed;

  /// See [AiAuditSummary.notes].
  final List<String> aiNotes;

  /// Null when the audit was fine. A failed audit never fails the sync, so
  /// this is the only trace of it.
  final String? aiError;

  final SyncStage stage;

  const SyncReport({
    required this.startedAt,
    this.duration = Duration.zero,
    this.emailsFetched = 0,
    this.subscriptionsFound = 0,
    this.billsFound = 0,
    this.deliveriesFound = 0,
    this.eventsFound = 0,
    this.unclaimedCount = 0,
    this.knowledgeApplied = 0,
    this.typesLearned = 0,
    this.learnedLabels = const [],
    this.aiRan = false,
    this.aiRejected = 0,
    this.aiRenamed = 0,
    this.aiNotes = const [],
    this.aiError,
    this.stage = SyncStage.done,
  });

  /// "Never synced" — what the Processing screen shows on a fresh install.
  /// [startedAt] is the epoch because a null date would force every consumer
  /// to null-check a field that is otherwise always present.
  factory SyncReport.empty() => SyncReport(
    startedAt: DateTime.fromMillisecondsSinceEpoch(0),
    stage: SyncStage.idle,
  );

  /// True for [SyncReport.empty] — nothing has ever run.
  bool get neverSynced => stage == SyncStage.idle && emailsFetched == 0;

  int get totalInsights =>
      subscriptionsFound + billsFound + deliveriesFound + eventsFound;

  /// Share of insights the audit threw away. 0 when there were no insights —
  /// an empty scan is not a 100% failure rate.
  double get aiRejectRate =>
      totalInsights == 0 ? 0 : aiRejected / totalInsights;

  /// Insights the AI touched at all.
  int get aiCorrections => aiRejected + aiRenamed;

  /// One sentence, e.g. "Read 84 emails, found 19 insights, AI corrected 3."
  /// Drops the AI clause when the model did not run or changed nothing, and
  /// collapses to "nothing new" when the scan came up empty — a row of zeros
  /// reads as a bug, a plain sentence reads as an answer.
  String get headline {
    if (stage == SyncStage.failed) {
      return 'Scan failed${aiError == null ? '' : ' — $aiError'}.';
    }
    if (neverSynced) return 'No scan yet.';
    if (emailsFetched == 0) return 'No new mail.';

    final read = 'Read $emailsFetched ${_plural(emailsFetched, 'email')}';
    if (totalInsights == 0) return '$read, nothing new.';

    final found = 'found $totalInsights ${_plural(totalInsights, 'insight')}';
    if (aiError != null) return '$read, $found — AI check failed.';
    if (!aiRan || aiCorrections == 0) return '$read, $found.';
    return '$read, $found, AI corrected $aiCorrections.';
  }

  /// Short lines for a detail list: ['8 subscriptions', '4 bills',
  /// '5 packages', '2 meetings']. Zero entries are omitted entirely — a list
  /// of "0 bills" rows is noise, and the categories a user has nothing in are
  /// not news.
  List<String> get breakdown => [
    if (subscriptionsFound > 0)
      '$subscriptionsFound ${_plural(subscriptionsFound, 'subscription')}',
    if (billsFound > 0) '$billsFound ${_plural(billsFound, 'bill')}',
    if (deliveriesFound > 0)
      '$deliveriesFound ${_plural(deliveriesFound, 'package')}',
    if (eventsFound > 0) '$eventsFound ${_plural(eventsFound, 'meeting')}',
  ];

  SyncReport copyWith({
    DateTime? startedAt,
    Duration? duration,
    int? emailsFetched,
    int? subscriptionsFound,
    int? billsFound,
    int? deliveriesFound,
    int? eventsFound,
    int? unclaimedCount,
    int? knowledgeApplied,
    int? typesLearned,
    List<String>? learnedLabels,
    bool? aiRan,
    int? aiRejected,
    int? aiRenamed,
    List<String>? aiNotes,
    String? aiError,
    bool clearAiError = false,
    SyncStage? stage,
  }) => SyncReport(
    startedAt: startedAt ?? this.startedAt,
    duration: duration ?? this.duration,
    emailsFetched: emailsFetched ?? this.emailsFetched,
    subscriptionsFound: subscriptionsFound ?? this.subscriptionsFound,
    billsFound: billsFound ?? this.billsFound,
    deliveriesFound: deliveriesFound ?? this.deliveriesFound,
    eventsFound: eventsFound ?? this.eventsFound,
    unclaimedCount: unclaimedCount ?? this.unclaimedCount,
    knowledgeApplied: knowledgeApplied ?? this.knowledgeApplied,
    typesLearned: typesLearned ?? this.typesLearned,
    learnedLabels: learnedLabels ?? this.learnedLabels,
    aiRan: aiRan ?? this.aiRan,
    aiRejected: aiRejected ?? this.aiRejected,
    aiRenamed: aiRenamed ?? this.aiRenamed,
    aiNotes: aiNotes ?? this.aiNotes,
    // Explicit clear: a successful re-audit has to be able to erase the
    // previous error, which `?? this.aiError` alone can never do.
    aiError: clearAiError ? null : (aiError ?? this.aiError),
    stage: stage ?? this.stage,
  );

  /// Folds an audit summary in, so the sync engine does not have to unpack it
  /// field by field.
  SyncReport withAudit(AiAuditSummary audit, {String? error}) => copyWith(
    aiRan: true,
    aiRejected: audit.rejected,
    aiRenamed: audit.renamed,
    aiNotes: audit.notes,
    aiError: error,
    clearAiError: error == null,
  );

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'emailsFetched': emailsFetched,
    'subscriptionsFound': subscriptionsFound,
    'billsFound': billsFound,
    'deliveriesFound': deliveriesFound,
    'eventsFound': eventsFound,
    'unclaimedCount': unclaimedCount,
    'knowledgeApplied': knowledgeApplied,
    'typesLearned': typesLearned,
    'learnedLabels': learnedLabels,
    'aiRan': aiRan,
    'aiRejected': aiRejected,
    'aiRenamed': aiRenamed,
    'aiNotes': aiNotes,
    'aiError': aiError,
    'stage': stage.name,
  };

  /// Tolerant of missing keys: this is read back from a stored preference
  /// that older builds wrote with fewer fields, and a missing count must
  /// never lose the whole report.
  factory SyncReport.fromJson(Map<String, dynamic> json) => SyncReport(
    startedAt: json['startedAt'] == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.parse(json['startedAt'] as String),
    duration: Duration(
      milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
    ),
    emailsFetched: (json['emailsFetched'] as num?)?.toInt() ?? 0,
    subscriptionsFound: (json['subscriptionsFound'] as num?)?.toInt() ?? 0,
    billsFound: (json['billsFound'] as num?)?.toInt() ?? 0,
    deliveriesFound: (json['deliveriesFound'] as num?)?.toInt() ?? 0,
    eventsFound: (json['eventsFound'] as num?)?.toInt() ?? 0,
    unclaimedCount: (json['unclaimedCount'] as num?)?.toInt() ?? 0,
    knowledgeApplied: (json['knowledgeApplied'] as num?)?.toInt() ?? 0,
    typesLearned: (json['typesLearned'] as num?)?.toInt() ?? 0,
    learnedLabels:
        ((json['learnedLabels'] ?? const []) as List).whereType<String>().toList(),
    aiRan: json['aiRan'] as bool? ?? false,
    aiRejected: (json['aiRejected'] as num?)?.toInt() ?? 0,
    aiRenamed: (json['aiRenamed'] as num?)?.toInt() ?? 0,
    aiNotes: ((json['aiNotes'] ?? const []) as List)
        .map((e) => e.toString())
        .toList(),
    aiError: json['aiError'] as String?,
    stage: SyncStage.values.firstWhere(
      (s) => s.name == json['stage'],
      orElse: () => SyncStage.idle,
    ),
  );
}
