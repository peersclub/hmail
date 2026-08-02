import 'package:flutter/cupertino.dart';

import '../core/brand_icons.dart';
import '../core/palette.dart';
import '../domain/insight.dart';
import 'action_sheet.dart';
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
      onTap: insight.actions.isEmpty
          ? null
          : () => showInsightActions(
                context,
                title: insight.title,
                actions: insight.actions,
              ),
    );
  }
}
