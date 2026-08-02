/// Insight → action bridge for the UI.
///
/// Tapping an insight opens a sheet of what can be done with it. Each row
/// says where it will land — "Track package · Delhivery" when the app is
/// installed, "in NoMail" when it will open in the in-app browser — because
/// a tap that leaves the app unexpectedly is the thing people dislike most
/// about deep links.
library;

import 'package:flutter/cupertino.dart';

import '../core/action_launcher.dart';
import '../core/brand_icons.dart';
import '../core/installed_apps.dart';
import '../core/palette.dart';
import '../domain/actions.dart';
import '../domain/deep_links.dart';
import '../domain/link_feedback.dart';

/// Shared across the app so the ~43 scheme probes happen once per session.
final InstalledApps installedApps = InstalledApps();

Future<void> showInsightActions(
  BuildContext context, {
  required String title,
  String? message,
  required List<InsightAction> actions,
  String? insightId,
  String? knowledgeTypeId,
  Future<void> Function(LinkFeedback)? onFeedback,
}) async {
  if (actions.isEmpty) return;

  // Never make the user wait on ~43 scheme probes to see a sheet. The sweep
  // is warmed at app start; if it somehow hasn't finished, fall back to
  // "nothing installed", which only ever routes to the web — safe, and
  // corrected by the time of the next tap.
  final installed = installedApps.isReady
      ? installedApps.known
      : await installedApps
          .detect()
          .timeout(const Duration(milliseconds: 250), onTimeout: () => const {});
  if (!context.mounted) return;

  final plans = {
    for (final action in actions) action: planFor(action, installed),
  };

  if (actions.length == 1) {
    await _launchWithFallback(
      context, actions.single, actions, plans,
      insightId: insightId,
      knowledgeTypeId: knowledgeTypeId,
      onFeedback: onFeedback,
    );
    return;
  }

  await showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final action in actions)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              _launchWithFallback(
                context, action, actions, plans,
                insightId: insightId,
                knowledgeTypeId: knowledgeTypeId,
                onFeedback: onFeedback,
              );
            },
            child: _ActionRow(action: action, plan: plans[action]),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(sheetContext),
        child: const Text('Cancel'),
      ),
    ),
  );
}

/// What a row promises will happen on tap.
///
/// Three outcomes, three markers, always in the same place: the app's own
/// mark and name when we detected it, a globe for "stays in NoMail", and an
/// out-arrow for "leaves for Safari". A tap that leaves the app unexpectedly
/// is the thing people dislike most about deep links, and the cure is simply
/// saying so beforehand.
({IconData icon, String label}) destinationHint(LinkPlan plan) =>
    switch (plan.mode) {
      // Simple Icons omits many trademarks (Delhivery, Flipkart…); a generic
      // app mark is better than a wrong logo.
      LinkOpenMode.nativeApp => (
          icon: BrandIcons.forText([plan.destination, plan.appKey]) ??
              CupertinoIcons.app_badge,
          label: plan.destination,
        ),
      LinkOpenMode.inAppWebView => (
          icon: CupertinoIcons.globe,
          label: 'in NoMail',
        ),
      // `destination` here is either a named handler ("your UPI app") or the
      // browser; either way the arrow says the app is being left.
      LinkOpenMode.systemHandoff => (
          icon: CupertinoIcons.arrow_up_right_square,
          label: plan.destination,
        ),
    };

/// One sheet row: the action, then its destination hint in muted text.
class _ActionRow extends StatelessWidget {
  final InsightAction action;
  final LinkPlan? plan;

  const _ActionRow({required this.action, this.plan});

  @override
  Widget build(BuildContext context) {
    final currentPlan = plan;
    if (currentPlan == null) return Text(action.label);
    final hint = destinationHint(currentPlan);
    final muted = Palette.secondaryLabel(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(action.label, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Icon(hint.icon, size: 14, color: muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            hint.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ),
      ],
    );
  }
}

/// Nothing on the device could handle the deep link (a upi:// intent with no
/// UPI app)? Fall back to the insight's own email — the source of truth, and
/// a URL that always opens. A tap must never end in silence.
Future<void> _launchWithFallback(
  BuildContext context,
  InsightAction action,
  List<InsightAction> all,
  Map<InsightAction, LinkPlan> plans, {
  String? insightId,
  String? knowledgeTypeId,
  Future<void> Function(LinkFeedback)? onFeedback,
}) async {
  final plan = plans[action];
  final opened = plan == null
      ? await openAction(action)
      : await openPlanned(
          plan,
          action: action,
          context: context,
          insightId: insightId,
          knowledgeTypeId: knowledgeTypeId,
          onFeedback: onFeedback,
        );
  if (opened) return;

  if (action.kind == ActionKind.openEmail) return; // already the fallback
  for (final candidate in all) {
    if (candidate.kind == ActionKind.openEmail) {
      await openAction(candidate);
      return;
    }
  }
}
