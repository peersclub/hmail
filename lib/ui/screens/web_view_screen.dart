/// In-app browser for links whose native app isn't installed.
///
/// Handing a tracking or payment link to Safari ends NoMail's involvement: the
/// user leaves, something happens, and we never learn what. Keeping the page
/// inside the app costs one screen and buys the only feedback loop we have on
/// URLs the app *constructed* — one question at the bottom of the page,
/// answered or ignored, written to [LinkFeedbackLog].
///
/// This is why it's a real WKWebView (`webview_flutter`) and not
/// `LaunchMode.inAppBrowserView`: SFSafariViewController renders a page and
/// tells us nothing about it — no navigation callbacks, no chrome of our own,
/// nowhere to put the question.
library;

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/palette.dart';
import '../../domain/link_feedback.dart';
import '../glass/glass.dart';

class WebViewScreen extends StatefulWidget {
  final Uri url;
  final String title;
  final String? insightId;
  final String? sourceEmailId;

  /// The learned recipe that produced [url], when it wasn't a literal link
  /// from the email. Passing it is what makes the feedback actionable.
  final String? knowledgeTypeId;

  final Future<void> Function(LinkFeedback)? onFeedback;

  const WebViewScreen({
    super.key,
    required this.url,
    required this.title,
    this.insightId,
    this.sourceEmailId,
    this.knowledgeTypeId,
    this.onFeedback,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;

  /// 0–100. Drives the hairline under the nav bar.
  int _progress = 0;
  bool _loading = true;

  /// Set only for main-frame failures. Subresource errors (a tracking pixel, a
  /// font, an ad script) fire constantly on real merchant pages and must never
  /// replace a page the user can read.
  String? _mainFrameError;

  /// The URL the question currently refers to — the last page that finished
  /// loading, not every redirect hop along the way.
  String? _pageUrl;

  /// URLs already answered (or auto-resolved) this session. The prompt appears
  /// once per URL: an interrogation on every tap trains people to dismiss it,
  /// which is worse than never asking.
  final Set<String> _resolved = <String>{};

  /// True once a dismissal has been written for the pending question, so
  /// leaving the screen records `dismissed` exactly once.
  bool _dismissalRecorded = false;

  /// Non-http(s) navigations we blocked. Kept so the user is told why the page
  /// stalled, and offered the hand-off to the OS that the page was asking for.
  Uri? _blockedScheme;
  int _blockedCount = 0;

  static const _externalSchemes = <String>{
    'upi',
    'tel',
    'mailto',
    'sms',
    'itms-apps',
    'itms-appss',
  };

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _progress = 0;
              _mainFrameError = null;
            });
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            final signIn = await _looksLikeLoginWall(url);
            if (!mounted) return;
            setState(() {
              _loading = false;
              _progress = 100;
              _pageUrl = url;
              // A sign-in wall answers itself: our WebView has no session, so
              // asking the user whether this is "the right page" would just
              // harvest a false accusation against a correct URL.
              if (signIn && _resolved.add(url)) {
                _record(LinkOutcome.loginWall, url: url);
              }
            });
          },
          onWebResourceError: _onWebResourceError,
        ),
      )
      ..loadRequest(widget.url);
  }

  @override
  void dispose() {
    // Leaving without answering is itself data: it separates "we asked and got
    // nothing" from "we never asked".
    if (_askVisible && !_dismissalRecorded) {
      _dismissalRecorded = true;
      _record(LinkOutcome.dismissed, url: _pendingUrl);
    }
    super.dispose();
  }

  String get _pendingUrl => _pageUrl ?? widget.url.toString();

  /// Path fragments that essentially only appear on auth screens. Matched on
  /// the *landed* URL, so a redirect from `/track/AWB123` to `/login` is
  /// caught even though the link we opened looked fine.
  static const _loginPaths = [
    '/login',
    '/signin',
    '/sign-in',
    '/sign_in',
    '/auth',
    '/session/new',
    '/account/login',
    '/customer/account/login',
    'returnurl=',
    'redirect_uri=',
  ];

  /// True when the page we landed on is asking for credentials. Checks the
  /// URL first (cheap, no JS) and only then the title, because a title can
  /// legitimately contain "sign in" on a page that isn't a login form.
  Future<bool> _looksLikeLoginWall(String url) async {
    final lower = url.toLowerCase();
    if (_loginPaths.any(lower.contains)) return true;
    try {
      final title = (await _controller.getTitle())?.toLowerCase() ?? '';
      return title.startsWith('sign in') ||
          title.startsWith('log in') ||
          title.startsWith('login');
    } catch (_) {
      return false;
    }
  }

  /// The question is shown only when there is a readable page, the load has
  /// settled, and this URL hasn't been resolved yet.
  bool get _askVisible =>
      _mainFrameError == null &&
      !_loading &&
      !_resolved.contains(_pendingUrl) &&
      _pendingUrl != 'about:blank';

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final target = Uri.tryParse(request.url);
    final scheme = target?.scheme.toLowerCase() ?? '';
    if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
      return NavigationDecision.navigate;
    }

    // `upi:`, `tel:`, `mailto:`, `itms-apps:` … a WKWebView cannot load these;
    // attempting it leaves a blank frame. They belong to the OS, so we stop
    // the navigation, remember it, and offer the hand-off explicitly.
    if (target != null && mounted) {
      setState(() {
        _blockedScheme = target;
        _blockedCount++;
      });
    }
    return NavigationDecision.prevent;
  }

  void _onWebResourceError(WebResourceError error) {
    if (error.isForMainFrame != true) return; // Subresource noise.
    if (!mounted) return;
    final failed = _pendingUrl;
    setState(() {
      _loading = false;
      _mainFrameError = error.description.isEmpty
          ? 'The page could not be loaded.'
          : error.description;
    });
    // A load that failed needs no human confirmation — record it and don't ask.
    if (_resolved.add(failed)) {
      _record(LinkOutcome.brokenLink, url: failed);
    }
  }

  void _record(LinkOutcome outcome, {required String url}) {
    final callback = widget.onFeedback;
    if (callback == null) return;
    // Fire and forget: persistence must never block the UI, and this also runs
    // from dispose() where awaiting is not an option.
    callback(
      LinkFeedback(
        url: url,
        insightId: widget.insightId,
        sourceEmailId: widget.sourceEmailId,
        knowledgeTypeId: widget.knowledgeTypeId,
        outcome: outcome,
        at: DateTime.now(),
      ),
    ).catchError((_) {});
  }

  void _answer(LinkOutcome outcome) {
    final url = _pendingUrl;
    // Marking the URL resolved hides the question, never the page: the user may
    // well want to keep reading the thing they just told us was wrong.
    setState(() => _resolved.add(url));
    _record(outcome, url: url);
  }

  Future<void> _handOffBlocked() async {
    final target = _blockedScheme;
    if (target == null) return;
    setState(() => _blockedScheme = null);
    try {
      await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No handler installed. The notice is already gone; nothing to undo.
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: CupertinoNavigationBar(
          backgroundColor: const Color(0x00000000),
          border: null,
          middle: _title(context),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(
              'Done',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Palette.label(context),
              ),
            ),
          ),
        ),
        child: Column(
          children: [
            _progressLine(context),
            Expanded(
              child: Stack(
                children: [
                  if (_mainFrameError == null)
                    Positioned.fill(child: WebViewWidget(controller: _controller))
                  else
                    Positioned.fill(child: _errorState(context)),
                  if (_loading && _mainFrameError == null)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _bottomBar(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: Palette.label(context),
          ),
        ),
        Text(
          widget.url.host,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: Palette.secondaryLabel(context),
          ),
        ),
      ],
    );
  }

  /// Determinate hairline: a page that is 40% loaded says something an
  /// indeterminate spinner cannot.
  Widget _progressLine(BuildContext context) {
    final visible = _loading && _mainFrameError == null;
    return SizedBox(
      height: 2,
      child: visible
          ? LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: constraints.maxWidth * (_progress.clamp(0, 100) / 100),
                  height: 2,
                  color: Palette.accent(context),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _errorState(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          GlassEmptyState(
            icon: CupertinoIcons.wifi_exclamationmark,
            title: 'This link did not open',
            caption: _mainFrameError ?? 'The page could not be loaded.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AccentButton(
              'Try again',
              onPressed: () {
                setState(() {
                  _mainFrameError = null;
                  _loading = true;
                  _progress = 0;
                });
                _controller.loadRequest(widget.url);
              },
            ),
          ),
          const Footnote(
            'Noted as a broken link. NoMail uses this to stop suggesting '
            'links built the same way.',
          ),
        ],
      ),
    );
  }

  /// Blocked-scheme notice and the feedback question share the bottom slot —
  /// two stacked prompts would be one too many.
  Widget _bottomBar(BuildContext context) {
    final Widget? content = _blockedScheme != null
        ? _blockedNotice(context)
        : (_askVisible ? _feedbackBar(context) : null);
    if (content == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: content,
    );
  }

  Widget _feedbackBar(BuildContext context) {
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Did this open the right page?',
              style: TextStyle(
                fontSize: 15,
                letterSpacing: -0.2,
                color: Palette.label(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _answerButton(
            context,
            icon: CupertinoIcons.hand_thumbsup,
            label: 'Yes',
            onPressed: () => _answer(LinkOutcome.worked),
          ),
          const SizedBox(width: 6),
          _answerButton(
            context,
            icon: CupertinoIcons.hand_thumbsdown,
            label: 'Wrong page',
            onPressed: () => _answer(LinkOutcome.wrongPage),
          ),
        ],
      ),
    );
  }

  Widget _answerButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Palette.badgeFill(context),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: Palette.label(context)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Palette.label(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockedNotice(BuildContext context) {
    final target = _blockedScheme!;
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const IconBadge(CupertinoIcons.arrow_up_right_square, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This page wants to open ${target.scheme}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    letterSpacing: -0.2,
                    color: Palette.label(context),
                  ),
                ),
                Text(
                  _externalSchemes.contains(target.scheme.toLowerCase())
                      ? 'Handled outside NoMail'
                      : 'Not a web link',
                  style: TextStyle(
                    fontSize: 12,
                    color: Palette.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _answerButton(
            context,
            icon: CupertinoIcons.arrow_up_right,
            label: 'Open',
            onPressed: _handOffBlocked,
          ),
          const SizedBox(width: 6),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => setState(() => _blockedScheme = null),
            child: Icon(
              CupertinoIcons.xmark,
              size: 16,
              color: Palette.secondaryLabel(context),
            ),
          ),
        ],
      ),
    );
  }

  /// How many non-web navigations this page attempted. Exposed for diagnostics
  /// and tests; a page that keeps reaching for `upi:` is a page we routed here
  /// when we should have handed it straight to the OS.
  int get blockedNavigationCount => _blockedCount;
}
