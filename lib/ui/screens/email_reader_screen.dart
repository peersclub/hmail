/// Reading the source email, inside NoMail.
///
/// WHY NOT JUST OPEN GMAIL
/// On iOS there is no reliable hand-off. `mail.google.com` publishes no
/// `apple-app-site-association` naming the Gmail app, so its https URL lands
/// in Safari every time — and Safari is a different session from the app, so
/// people routinely arrive at a sign-in wall instead of their email. The
/// `googlegmail://` scheme exists but Google has never documented its message
/// URL format. Rendering the body ourselves is the only path that always
/// works. Gmail is still one tap away in the nav bar, for when the user wants
/// to reply or archive.
///
/// WHY THIS IS SAFE WHERE A WEBVIEW USUALLY IS NOT
/// `loadHtmlString` puts a document in the WebView with no origin and no
/// navigation, so the cookie jar that makes logged-in pages render signed-out
/// is never consulted — the thing being displayed is text we already hold. A
/// Content-Security-Policy then bounds what the message may do: scripts and
/// network access are off, and remote images stay off until the user asks,
/// because loading them is what tells a sender their mail was opened. That is
/// the same bargain every mail client makes, stated in one header rather than
/// spread across a sanitiser.
///
/// Links are not followed here. A tap leaves for the existing routing layer,
/// so an email's buttons behave exactly like an insight's buttons do.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/action_launcher.dart';
import '../../core/palette.dart';
import '../../data/mail/message_reader.dart';
import '../../domain/actions.dart';
import '../../domain/deep_links.dart';
import '../action_sheet.dart';
import '../glass/glass.dart';

class EmailReaderScreen extends StatefulWidget {
  /// The id as insights carry it — `a<N>:` prefix included, since that is what
  /// tells [MessageReader] which account to ask.
  final String sourceEmailId;

  /// Shown while the body is still in flight, so the screen is never blank.
  final String? fallbackTitle;

  const EmailReaderScreen({
    super.key,
    required this.sourceEmailId,
    this.fallbackTitle,
  });

  @override
  State<EmailReaderScreen> createState() => _EmailReaderScreenState();
}

class _EmailReaderScreenState extends State<EmailReaderScreen> {
  late final WebViewController _controller;

  MessageBody? _body;
  bool _loading = true;
  bool _failed = false;

  /// Off until asked. A remote image in an email is usually a tracking pixel,
  /// and fetching it reports the open — with the device's IP — to whoever sent
  /// it. Blocking by default is the only choice that doesn't make that
  /// decision on the user's behalf.
  bool _showImages = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // Nothing in a message needs to run. The CSP says so too; this says it
      // at the engine, where no `<meta>` can be worked around.
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _onNavigationRequest),
      );
    _load();
  }

  Future<void> _load() async {
    final body = await messageReader.fetch(widget.sourceEmailId);
    if (!mounted) return;
    if (body == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    setState(() {
      _body = body;
      _loading = false;
    });
    await _render();
  }

  Future<void> _render() async {
    final body = _body;
    if (body == null) return;
    await _controller.loadHtmlString(
      _document(body, showImages: _showImages, dark: Palette.isDark(context)),
    );
  }

  /// A tap inside the message. The document itself arrives via
  /// [WebViewController.loadHtmlString], which reports as `about:blank`, so
  /// anything else is the user following a link — and links out of an email go
  /// through the same routing every other link in the app does, rather than
  /// navigating this WebView into a page it has no session for.
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null || request.url == 'about:blank') {
      return NavigationDecision.navigate;
    }
    final action = InsightAction(
      label: 'Open link',
      uri: uri,
      kind: ActionKind.openLink,
    );
    unawaited(_openOutside(action));
    return NavigationDecision.prevent;
  }

  Future<void> _openOutside(InsightAction action) async {
    final installed = installedApps.isReady ? installedApps.known : const <String>{};
    await openPlanned(
      planFor(action, installed),
      action: action,
      context: mounted ? context : null,
    );
  }

  /// Opens the message on the web, for replying or archiving.
  ///
  /// Safari, not the Gmail app: there is no working hand-off to it on iOS, and
  /// the scheme URL that looked like one made Gmail show its own "unable to
  /// understand link" error. Safari may ask the user to sign in — annoying,
  /// but it is a page they can act on, which is the point of this button.
  Future<void> _openOnTheWeb() async {
    await _openOutside(openEmailAction(widget.sourceEmailId));
  }

  Future<void> _toggleImages() async {
    setState(() => _showImages = !_showImages);
    await _render();
  }

  @override
  Widget build(BuildContext context) {
    final body = _body;
    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: CupertinoNavigationBar(
          backgroundColor: const Color(0x00000000),
          border: null,
          middle: Text(
            body?.subject.isNotEmpty == true
                ? body!.subject
                : widget.fallbackTitle ?? 'Email',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, color: Palette.label(context)),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (body != null && body.isRichText)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: _toggleImages,
                  child: Semantics(
                    label: _showImages
                        ? 'Hide images'
                        : 'Load images — tells the sender you opened this',
                    child: Icon(
                      _showImages
                          ? CupertinoIcons.photo_fill
                          : CupertinoIcons.photo,
                      size: 21,
                      color: Palette.secondaryLabel(context),
                    ),
                  ),
                ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: _openOnTheWeb,
                child: Semantics(
                  label: 'Open this message in Gmail on the web',
                  child: Icon(
                    CupertinoIcons.arrow_up_right_square,
                    size: 21,
                    color: Palette.secondaryLabel(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        child: SafeArea(child: _content()),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_failed) {
      final signedIn = messageReader.isAvailable;
      return GlassEmptyState(
        icon: CupertinoIcons.envelope_badge,
        title: 'Couldn\'t load this email',
        // Deleted, or the account it lived in was disconnected. Both are
        // ordinary outcomes, so the tone stays flat and a way out is offered
        // rather than leaving the user on a dead screen.
        caption: signedIn
            ? 'It may have been deleted, or its account is no longer '
                'connected.'
            : 'Sign in to read the original message.',
        actionLabel: signedIn ? 'Open on the web' : null,
        onAction: signedIn ? _openOnTheWeb : null,
      );
    }
    return WebViewWidget(controller: _controller);
  }
}

/// Wraps a message body in a document that cannot phone home.
///
/// The CSP is the whole security model, so it is written out rather than
/// generated: `default-src 'none'` denies everything, and each allowance is
/// added back deliberately. `style-src 'unsafe-inline'` is unavoidable —
/// email styling is inline by nature — and is harmless with scripts denied.
/// `img-src data:` still admits embedded images, which are already in the
/// message and cost no request.
String _document(
  MessageBody body, {
  required bool showImages,
  required bool dark,
}) {
  final imgSrc = showImages ? 'data: https: http:' : 'data:';
  // Rich HTML brings its own colours, almost always dark-on-white. Recolouring
  // it for dark mode is how mail clients produce black text on black; the
  // message gets its white sheet. Plain text has no colours of its own, so it
  // follows the app.
  final surface = body.isRichText ? '#ffffff' : (dark ? '#000000' : '#ffffff');
  final ink = body.isRichText ? '#111111' : (dark ? '#f2f2f7' : '#111111');
  final muted = dark && !body.isRichText ? '#98989f' : '#6b6b70';

  return '''<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src $imgSrc; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'">
<style>
  html { -webkit-text-size-adjust: 100%; background: $surface; }
  body {
    margin: 0; padding: 16px;
    background: $surface; color: $ink;
    font: 16px/1.5 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
    /* Emails are built on fixed-width tables; let them scroll rather than
       forcing a reflow that breaks the sender's layout. */
    overflow-x: auto;
  }
  .nm-head { border-bottom: 1px solid rgba(120,120,128,0.24);
             padding-bottom: 12px; margin-bottom: 16px; }
  .nm-from { font-size: 15px; font-weight: 600; color: $ink; }
  .nm-date { font-size: 13px; color: $muted; margin-top: 2px; }
  img { max-width: 100%; height: auto; }
  pre { white-space: pre-wrap; word-wrap: break-word;
        font: 15px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
  a { color: #0a84ff; }
</style>
</head><body>
<div class="nm-head">
  <div class="nm-from">${escapeHtml(body.from)}</div>
  <div class="nm-date">${escapeHtml(_stamp(body.date))}</div>
</div>
${body.html}
</body></html>''';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _stamp(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${_months[date.month - 1]} ${date.year}, '
      '$hour:$minute ${date.hour < 12 ? 'am' : 'pm'}';
}
