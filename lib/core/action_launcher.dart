/// The one impure step of the actions pipeline: handing a URI somewhere.
///
/// `domain/deep_links.dart` decides *where* a link should open — the native
/// app, an in-app WebView, or iOS. This performs that decision. Native and
/// system hand-offs both use `externalApplication` launch mode, which is what
/// makes universal links reach their app and `upi://` reach a payment app;
/// the WebView path is a Flutter route, so it needs a navigator rather than
/// the OS.
library;

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/actions.dart';
import '../domain/deep_links.dart';
import '../domain/link_feedback.dart';
import '../ui/screens/email_reader_screen.dart';
import '../ui/screens/web_view_screen.dart';

/// Hands [action] to iOS. False means nothing on the device took it.
///
/// Both outcomes that mean "no handler" arrive here as false: `url_launcher`
/// returns false when `UIApplication.open` reports failure, and throws only
/// when the URL itself won't parse; the catch folds that into the same answer,
/// because to a caller looking for something else to try they are one event.
///
/// What false does *not* cover, and the reason this app no longer constructs
/// scheme URLs: a scheme that is registered but whose path the receiving app
/// can't parse. iOS reports the hand-off, not the app's comprehension, so that
/// returns **true** while the user looks at the other app's error dialog. A
/// guessed `app://path` therefore cannot be made safe by falling back on
/// false — see the note in `domain/actions.dart`.
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
///
/// [LinkOpenMode.emailReader] is the other in-app route and needs a [context]
/// for the same reason. It degrades to the plan's URL without one, which for
/// "Open email" means Safari — worse, but never nothing.
Future<bool> openPlanned(
  LinkPlan plan, {
  required InsightAction action,
  BuildContext? context,
  String? insightId,
  String? knowledgeTypeId,
  Future<void> Function(LinkFeedback)? onFeedback,
}) async {
  final emailId = action.sourceEmailId;
  if (plan.mode == LinkOpenMode.emailReader &&
      emailId != null &&
      context != null &&
      context.mounted) {
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => EmailReaderScreen(
          sourceEmailId: emailId,
          fallbackTitle: action.label,
        ),
      ),
    );
    return true;
  }

  if (plan.mode != LinkOpenMode.inAppWebView ||
      context == null ||
      !context.mounted) {
    return openAction(InsightAction(
      label: action.label,
      uri: plan.uri,
      kind: action.kind,
      sourceEmailId: action.sourceEmailId,
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
