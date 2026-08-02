/// The one impure step of the actions pipeline: handing a URI somewhere.
///
/// `domain/deep_links.dart` decides *where* a link should open — the native
/// app, an in-app WebView, or iOS. This performs that decision. Native and
/// system hand-offs both use `externalApplication` launch mode, which is what
/// makes universal links reach their app and `upi://` reach a payment app;
/// the WebView path is a Flutter route, so it needs a navigator rather than
/// the OS.
library;

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/actions.dart';
import '../domain/deep_links.dart';
import '../domain/link_feedback.dart';
import '../ui/screens/web_view_screen.dart';

/// Hands [action] to iOS. Returns false when nothing could handle it (a
/// `upi://` link on a phone with no UPI app), so the caller can fall back.
Future<bool> openAction(InsightAction action) async {
  try {
    return await launchUrl(action.uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens [action] according to [plan].
///
/// The WebView needs a [context] to push onto; without one (a notification
/// tap, say) the plan degrades to the system browser rather than failing —
/// losing our feedback prompt is a far smaller cost than a dead tap.
Future<bool> openPlanned(
  LinkPlan plan, {
  required InsightAction action,
  BuildContext? context,
  String? insightId,
  String? knowledgeTypeId,
  Future<void> Function(LinkFeedback)? onFeedback,
}) async {
  if (plan.mode != LinkOpenMode.inAppWebView ||
      context == null ||
      !context.mounted) {
    return openAction(InsightAction(
      label: action.label,
      uri: plan.uri,
      kind: action.kind,
    ));
  }

  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => WebViewScreen(
        url: plan.uri,
        title: action.label,
        insightId: insightId,
        sourceEmailId: insightId,
        knowledgeTypeId: knowledgeTypeId,
        onFeedback: onFeedback,
      ),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
  return true;
}
