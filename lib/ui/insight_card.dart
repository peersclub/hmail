import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../core/brand_icons.dart';
import '../core/palette.dart';
import '../domain/insight.dart';
import '../state/app_controller.dart';
import 'action_sheet.dart';
import 'explain_sheet.dart';
import 'glass/glass.dart';

/// The one row that renders any [Insight], whatever its domain. Brand glyph
/// when the source is recognized, otherwise the category icon; tapping opens
/// the insight's actions. New insight types render through this unchanged.
class InsightCard extends StatelessWidget {
  final Insight insight;

  const InsightCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    final captionColor = insight.anchorDate == null && !insight.overdue
        ? null
        : Palette.urgency(context, insight.anchorDate, overdue: insight.overdue);

    return GlassRow(
      icon: BrandIcons.forName(insight.brandKey) ?? insight.icon,
      title: insight.title,
      titleMaxLines: 2,
      subtitle: insight.subtitle,
      subtitleMaxLines: 2,
      trailing: insight.trailing,
      trailingCaption: insight.caption,
      trailingCaptionColor: captionColor,
      trailingCaptionPill: insight.overdue,
      // Press and hold to ask what the row actually is. Offered only when it
      // can be answered — a gesture that always apologises teaches the user to
      // stop trying it.
      onLongPress: canExplain() && insight.sourceEmailId != null
          ? () => showExplanation(
                context,
                sourceEmailId: insight.sourceEmailId!,
                label: insight.title,
                context_: insight.subtitle,
              )
          : null,
      onTap: insight.actions.isEmpty
          ? null
          : () => showInsightActions(
                context,
                title: insight.title,
                // With several inboxes merged, say which one this came from —
                // a work bill and a personal bill must not be confusable.
                message: switch (context
                    .read<AppController>()
                    .accountForInsight(insight.id)) {
                  final String email => 'From $email',
                  null => null,
                },
                actions: insight.actions,
                correction: correctionFor(context, insight),
              ),
    );
  }
}

/// The "Not a bill" row for an insight, or null when it offers no correction.
///
/// Lives here rather than in the sheet because the sheet takes actions, not
/// insights — and the phrasing has to name the family the user is looking at
/// ("Not a package", "Not a subscription"), which only the insight knows.
({String label, Future<void> Function() run})? correctionFor(
  BuildContext context,
  Insight insight,
) {
  final kind = insight.ignoreKind;
  final subject = insight.correctionSubject;
  if (kind == null || subject == null) return null;

  final app = context.read<AppController>();
  return (
    label: 'Not a ${kind.noun}',
    run: () => app.ignoreInsight(kind, subject),
  );
}
