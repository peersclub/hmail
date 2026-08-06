/// Turns learned playbook matches into the app's typed insights.
///
/// The knowledge engine is deliberately generic — it extracts named fields
/// and builds URLs. This is the seam where that generality becomes a real
/// card: a learned "Delhivery shipment" type becomes a [Delivery] with a
/// tracking link, so learned knowledge lands in the same UI, ranking and
/// action machinery as the hand-written rules. Nothing here is AI; it runs
/// offline on every sync.
library;

import '../data/extractors/extractors.dart'
    show MoneyMatch, extractAllMoney, extractDate;
import 'knowledge.dart';
import 'models.dart';

/// Field names a learned type may use, in priority order. Learners are
/// prompted toward these, but a type that invents its own names still works —
/// it just falls back to the generic attention card.
const _trackingFields = ['trackingnumber', 'awb', 'trackingid', 'consignment'];
const _amountFields = ['amount', 'amountdue', 'total', 'totaldue'];
const _dateFields = ['duedate', 'date', 'when', 'start', 'eta'];

String _norm(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String? _pick(Map<String, String> fields, List<String> names) {
  for (final wanted in names) {
    for (final entry in fields.entries) {
      if (_norm(entry.key) == wanted && entry.value.trim().isNotEmpty) {
        return entry.value.trim();
      }
    }
  }
  return null;
}

/// The best URL a learned type produced, or null when it built none.
Uri? _primaryUri(KnowledgeMatch match) =>
    match.actions.isEmpty ? null : match.actions.first.uri;

/// Everything a sync learned to recognise, split into the typed buckets the
/// snapshot already understands.
class MappedKnowledge {
  final List<Subscription> subscriptions;
  final List<Bill> bills;
  final List<Delivery> deliveries;
  final List<EventItem> events;
  final List<LearnedItem> learned;
  final List<AttentionItem> attention;

  const MappedKnowledge({
    this.subscriptions = const [],
    this.bills = const [],
    this.deliveries = const [],
    this.events = const [],
    this.learned = const [],
    this.attention = const [],
  });

  bool get isEmpty =>
      subscriptions.isEmpty &&
      bills.isEmpty &&
      deliveries.isEmpty &&
      events.isEmpty &&
      learned.isEmpty &&
      attention.isEmpty;

  int get total =>
      subscriptions.length +
      bills.length +
      deliveries.length +
      events.length +
      learned.length +
      attention.length;
}

/// Maps `(email, match)` pairs onto typed insights.
///
/// A type that promises more than its fields deliver degrades rather than
/// fails: a `bill` with no parseable amount becomes an attention card with
/// its link intact, because losing the link is the only truly bad outcome.
MappedKnowledge mapKnowledge(List<(EmailMeta, KnowledgeMatch)> matches) {
  final subscriptions = <Subscription>[];
  final bills = <Bill>[];
  final deliveries = <Delivery>[];
  final events = <EventItem>[];
  final learned = <LearnedItem>[];
  final attention = <AttentionItem>[];

  for (final (email, match) in matches) {
    final label = match.type.label;
    final uri = _primaryUri(match);
    final fields = match.fields;

    void asAttention() => attention.add(AttentionItem(
          title: label,
          reason: match.subtitle ?? email.subject,
          date: email.date,
          sourceEmailId: email.id,
          linkUrl: uri?.toString(),
        ));

    switch (match.type.produces) {
      case ProducesKind.delivery:
        deliveries.add(Delivery(
          merchant: label,
          status: DeliveryStatus.shipped,
          trackingNumber: _pick(fields, _trackingFields),
          eta: _learnedDate(fields, email),
          lastSeen: email.date,
          sourceEmailId: email.id,
          trackingUrl: uri?.toString(),
        ));

      case ProducesKind.bill:
        final money = _learnedMoney(fields);
        if (money == null) {
          asAttention();
        } else {
          bills.add(Bill(
            issuer: label,
            amount: money.amount,
            currency: money.currency,
            dueDate: _learnedDate(fields, email),
            lastSeen: email.date,
            sourceEmailId: email.id,
            payUrl: uri?.toString(),
          ));
        }

      case ProducesKind.subscription:
        final money = _learnedMoney(fields);
        if (money == null) {
          asAttention();
        } else {
          subscriptions.add(Subscription(
            service: label,
            amount: money.amount,
            currency: money.currency,
            cadence: Cadence.unknown,
            nextRenewal: _learnedDate(fields, email),
            lastSeen: email.date,
            sourceEmailId: email.id,
            manageUrl: uri?.toString(),
          ));
        }

      case ProducesKind.event:
        final start = _learnedDate(fields, email);
        if (start == null) {
          asAttention();
        } else {
          events.add(EventItem(
            title: label,
            start: start,
            meetingUrl: uri?.toString(),
            lastSeen: email.date,
            sourceEmailId: email.id,
          ));
        }

      // A recipe for something the app was never taught to model — a school
      // fee circular, an insurance renewal, a visa appointment. It keeps its
      // own amount and its own deadline instead of being flattened into an
      // attention card dated by when the email happened to arrive.
      case ProducesKind.generic:
        final money = _learnedMoney(fields);
        learned.add(LearnedItem(
          label: label,
          typeId: match.type.id,
          summary: match.subtitle ?? email.subject,
          amount: money?.amount,
          currency: money?.currency ?? 'INR',
          deadline: _learnedDate(fields, email),
          url: uri?.toString(),
          lastSeen: email.date,
          sourceEmailId: email.id,
        ));
    }
  }

  return MappedKnowledge(
    subscriptions: subscriptions,
    bills: bills,
    deliveries: deliveries,
    events: events,
    learned: learned,
    attention: attention,
  );
}

MoneyMatch? _learnedMoney(Map<String, String> fields) {
  final raw = _pick(fields, _amountFields);
  if (raw == null) return null;
  final found = extractAllMoney(raw);
  if (found.isNotEmpty) return found.first;
  // A bare number in an amount field is still an amount; assume the
  // account's dominant currency rather than dropping the insight.
  final bare = double.tryParse(raw.replaceAll(RegExp(r'[,\s]'), ''));
  return bare == null || bare <= 0 ? null : MoneyMatch(bare, 'INR');
}

DateTime? _learnedDate(Map<String, String> fields, EmailMeta email) {
  final raw = _pick(fields, _dateFields);
  if (raw == null) return null;
  return extractDate(raw, anchor: email.date);
}
