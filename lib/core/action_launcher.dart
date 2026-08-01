/// The one impure step of the actions pipeline: handing a URI to the OS.
///
/// `domain/actions.dart` decides *what* can be done; this decides only *how*
/// to launch it. externalApplication mode is what makes deep links work —
/// upi:// intents reach payment apps, and universal links (mail.google.com,
/// calendar.google.com, zoom.us) open their native apps instead of an
/// in-app web view.
library;

import 'package:url_launcher/url_launcher.dart';

import '../domain/actions.dart';

/// Launches [action]; returns false when nothing on the device could handle
/// it (e.g. a upi:// link on a phone with no UPI app) so the UI can fall
/// back to the insight's "Open email" action.
Future<bool> openAction(InsightAction action) async {
  try {
    return await launchUrl(action.uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
