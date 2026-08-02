import 'package:flutter/cupertino.dart';

import '../ui/format.dart';
import 'actions.dart';
import 'insight.dart';
import 'models.dart';

/// Adapter layer: wraps the typed insight models in a snapshot into one
/// uniform `List<Insight>`. This is the single seam the whole type-driven UI
/// hangs off — adding a new insight type means adding one block here plus its
/// model and extractor, and nothing in the navigation or screens changes.
///
/// Weights encode the review's priority order:
///   security > money-at-risk > money-scheduled > logistics > content.
List<Insight> snapshotToInsights(InsightSnapshot s) {
  final out = <Insight>[];

  for (final b in s.unpaidUpcoming) {
    out.add(Insight(
      id: 'bill:${b.sourceEmailId}',
      domain: InsightDomain.money,
      title: b.issuer,
      trailing: formatMoney(b.amount, b.currency),
      caption: b.dueDate == null
          ? null
          : (b.isOverdue ? 'Overdue' : 'Due ${formatDay(b.dueDate!)}'),
      anchorDate: b.dueDate,
      overdue: b.isOverdue,
      icon: CupertinoIcons.doc_text_fill,
      brandKey: b.issuer,
      weight: b.isOverdue ? 90 : 70,
      actions: actionsForBill(b),
    ));
  }

  for (final sub in s.subscriptions) {
    out.add(Insight(
      id: 'sub:${sub.sourceEmailId}',
      domain: InsightDomain.money,
      title: sub.service,
      trailing: '${formatMoney(sub.amount, sub.currency)}/mo',
      caption: sub.nextRenewal == null
          ? null
          : 'Renews ${formatDay(sub.nextRenewal!)}',
      anchorDate: sub.nextRenewal,
      icon: CupertinoIcons.arrow_2_circlepath,
      brandKey: sub.service,
      weight: 55,
      actions: actionsForSubscription(sub),
    ));
  }

  for (final d in s.activeDeliveries) {
    out.add(Insight(
      id: 'delivery:${d.sourceEmailId}',
      domain: InsightDomain.commerce,
      title: d.merchant,
      subtitle: _deliveryStatus(d),
      caption: d.eta == null ? null : formatDay(d.eta!),
      anchorDate: d.eta,
      icon: CupertinoIcons.cube_box_fill,
      brandKey: d.merchant,
      weight: d.status == DeliveryStatus.outForDelivery ? 60 : 45,
      actions: actionsForDelivery(d),
    ));
  }

  for (final e in s.upcomingEvents) {
    out.add(Insight(
      id: 'event:${e.sourceEmailId}',
      domain: InsightDomain.work,
      title: e.title,
      subtitle: _eventTime(e),
      anchorDate: e.start,
      icon: CupertinoIcons.calendar,
      brandKey: e.organizer,
      weight: 50,
      actions: actionsForEvent(e),
    ));
  }

  for (final f in s.recentFeed) {
    out.add(Insight(
      id: 'feed:${f.sourceEmailId}',
      domain: InsightDomain.content,
      title: f.title,
      subtitle: '${f.source} · ${formatDay(f.date)}',
      anchorDate: null, // content is timeless — never outranks a deadline
      icon: _feedIcon(f.kind),
      brandKey: f.source,
      weight: 20,
      actions: [
        if (f.url != null)
          InsightAction(
            label: 'Open',
            uri: Uri.parse(f.url!),
            kind: ActionKind.openLink,
          ),
        openEmailAction(f.sourceEmailId),
      ],
    ));
  }

  for (final a in s.attention) {
    out.add(Insight(
      id: 'attention:${a.sourceEmailId}',
      domain: InsightDomain.security,
      title: a.title,
      subtitle: a.reason,
      anchorDate: a.date,
      icon: CupertinoIcons.exclamationmark_shield,
      weight: 100,
      actions: actionsForAttention(a),
    ));
  }

  return out;
}

/// Domains that currently have at least one insight — drives Timeline chips so
/// an empty category never shows an empty chip.
List<InsightDomain> presentDomains(List<Insight> insights) {
  final present = <InsightDomain>{for (final i in insights) i.domain};
  return InsightDomain.values.where(present.contains).toList();
}

String _deliveryStatus(Delivery d) => switch (d.status) {
      DeliveryStatus.outForDelivery => 'Out for delivery',
      DeliveryStatus.shipped => 'Shipped',
      DeliveryStatus.ordered => 'Order confirmed',
      DeliveryStatus.delivered => 'Delivered',
    };

String _eventTime(EventItem e) {
  final day = formatDay(e.start);
  final hour = e.start.hour % 12 == 0 ? 12 : e.start.hour % 12;
  final minute =
      e.start.minute == 0 ? '' : ':${e.start.minute.toString().padLeft(2, '0')}';
  final ampm = e.start.hour < 12 ? 'am' : 'pm';
  return (e.start.hour == 0 && e.start.minute == 0)
      ? day
      : '$day · $hour$minute$ampm';
}

IconData _feedIcon(FeedKind kind) => switch (kind) {
      FeedKind.article => CupertinoIcons.doc_richtext,
      FeedKind.newsletter => CupertinoIcons.envelope_open,
      FeedKind.video => CupertinoIcons.play_rectangle,
      FeedKind.podcast => CupertinoIcons.mic,
    };
