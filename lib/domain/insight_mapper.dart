import 'package:flutter/cupertino.dart';

import '../ui/format.dart';
import 'actions.dart';
import 'ignore_list.dart';
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
      ignoreKind: IgnoreKind.bill,
    ));
  }

  // Price moves outrank every scheduled money item (weight 85 sits above an
  // upcoming bill at 70, below an overdue one at 90): a hike is a decision the
  // user does not know they need to make, where a bill is one they already do.
  // Timeless on purpose — the anchor is the renewal it affects, and that
  // subscription already carries it.
  for (final c in s.activePriceChanges) {
    final up = c.isIncrease;
    out.add(Insight(
      id: 'price:${c.dedupeKey}',
      domain: InsightDomain.money,
      title: c.service,
      subtitle: '${up ? 'Price up' : 'Price down'} · '
          '${formatMoney(c.oldAmount, c.currency)} → '
          '${formatMoney(c.newAmount, c.currency)}',
      trailing: '${up ? '+' : '−'}'
          '${formatMoney(c.monthlyDelta.abs(), c.currency)}',
      caption: '/mo',
      icon: up
          ? CupertinoIcons.arrow_up_right_circle_fill
          : CupertinoIcons.arrow_down_right_circle_fill,
      brandKey: c.service,
      weight: 85,
      actions: actionsForPriceChange(c, s.subscriptions),
      // A price change is suppressed by correcting the subscription it
      // belongs to — two separate switches for one mistake would be worse
      // than one.
      ignoreKind: IgnoreKind.subscription,
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
      ignoreKind: IgnoreKind.subscription,
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
      ignoreKind: IgnoreKind.delivery,
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
      ignoreKind: IgnoreKind.event,
      // Recurring noise comes from the organiser, not the meeting title.
      ignoreSubject: e.organizer ?? e.title,
    ));
  }

  for (final p in s.activePayments) {
    final failed = p.kind == PaymentKind.failed;
    out.add(Insight(
      id: 'payment:${p.sourceEmailId}',
      domain: InsightDomain.money,
      title: p.source,
      subtitle: failed ? 'Payment failed' : 'Refund',
      trailing: p.amount == null ? null : formatMoney(p.amount!, p.currency),
      caption: failed ? 'Action needed' : 'Refunded',
      anchorDate: failed ? null : p.date,
      overdue: failed, // forces the imminent tier + red treatment
      icon: failed
          ? CupertinoIcons.exclamationmark_circle
          : CupertinoIcons.arrow_counterclockwise,
      brandKey: p.source,
      weight: failed ? 92 : 78,
      ignoreKind: IgnoreKind.payment,
      actions: [
        if (p.actionUrl != null)
          InsightAction(
            label: failed ? 'Fix payment' : 'View',
            uri: Uri.parse(p.actionUrl!),
            kind: ActionKind.openLink,
          ),
        openEmailAction(p.sourceEmailId),
      ],
    ));
  }

  for (final t in s.upcomingTravel) {
    final ref = t.code == null ? null : 'Ref ${t.code}';
    // Check-in open / boarding pass ready is the pressing state: it outranks a
    // plain confirmed trip and leads with the check-in action.
    out.add(Insight(
      id: 'travel:${t.sourceEmailId}',
      domain: InsightDomain.travel,
      title: t.route ?? t.provider,
      subtitle: t.boardingReady
          ? 'Check-in open'
          : (t.route != null
              ? [t.provider, if (ref != null) ref].join(' · ')
              : (ref ?? _travelLabel(t.kind))),
      caption: t.departure == null ? null : formatDay(t.departure!),
      anchorDate: t.departure,
      icon: t.boardingReady ? CupertinoIcons.ticket_fill : CupertinoIcons.airplane,
      brandKey: t.provider,
      weight: t.boardingReady ? 80 : 65,
      ignoreKind: IgnoreKind.travel,
      actions: [
        if (t.manageUrl != null)
          InsightAction(
            label: t.boardingReady ? 'Check in' : 'Manage booking',
            uri: Uri.parse(t.manageUrl!),
            kind: ActionKind.openLink,
          ),
        openEmailAction(t.sourceEmailId),
      ],
    ));
  }

  for (final r in s.openReturns) {
    final isReturn = r.kind == ReturnKind.returnWindow;
    out.add(Insight(
      id: 'return:${r.sourceEmailId}',
      domain: InsightDomain.commerce,
      title: r.merchant,
      subtitle: isReturn ? 'Return window' : 'Warranty',
      caption: '${isReturn ? 'Return by' : 'Expires'} ${formatDay(r.deadline)}',
      anchorDate: r.deadline,
      icon: isReturn
          ? CupertinoIcons.arrow_2_squarepath
          : CupertinoIcons.shield,
      brandKey: r.merchant,
      weight: 58,
      ignoreKind: IgnoreKind.returnItem,
      actions: [
        if (r.url != null)
          InsightAction(
            label: isReturn ? 'Start return' : 'View warranty',
            uri: Uri.parse(r.url!),
            kind: ActionKind.openLink,
          ),
        openEmailAction(r.sourceEmailId),
      ],
    ));
  }

  // Learned use-cases — the shapes the app taught itself. Weighted by what the
  // recipe actually managed to extract rather than by a flat constant: a dated
  // demand for money is a real errand and outranks a subscription, while a
  // recognised-but-featureless notice sits below one. Overclaiming here would
  // put the app's least certain output above its most certain.
  for (final l in s.activeLearned) {
    final hasMoney = l.amount != null;
    final hasDate = l.deadline != null;
    out.add(Insight(
      id: 'learned:${l.dedupeKey}',
      // Money if it found money, else a general-life bucket. Deliberately not
      // `security`, which is where these used to land as attention cards — a
      // school fee circular is not a security alert.
      domain: hasMoney ? InsightDomain.money : InsightDomain.personal,
      title: l.label,
      subtitle: l.summary,
      trailing: hasMoney ? formatMoney(l.amount!, l.currency) : null,
      caption: hasDate
          ? (l.isOverdue ? 'Overdue' : 'By ${formatDay(l.deadline!)}')
          : null,
      anchorDate: l.deadline,
      overdue: l.isOverdue,
      icon: hasMoney
          ? CupertinoIcons.doc_plaintext
          : CupertinoIcons.lightbulb,
      brandKey: l.label,
      weight: switch ((hasMoney, hasDate)) {
        (true, true) => 74,
        (true, false) => 62,
        (false, true) => 56,
        (false, false) => 30,
      },
      actions: actionsForLearned(l),
      ignoreKind: IgnoreKind.learned,
      ignoreSubject: l.label,
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
      ignoreKind: IgnoreKind.feed,
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
      // Security alerts are the one family where a wrong suppression is
      // dangerous, so the correction keys on the exact title rather than a
      // brand — it silences this alert, not everything from the sender.
      ignoreKind: IgnoreKind.attention,
      ignoreSubject: a.title,
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

String _travelLabel(TravelKind kind) => switch (kind) {
      TravelKind.flight => 'Flight',
      TravelKind.train => 'Train',
      TravelKind.hotel => 'Hotel',
      TravelKind.bus => 'Bus',
      TravelKind.cab => 'Cab',
    };

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
