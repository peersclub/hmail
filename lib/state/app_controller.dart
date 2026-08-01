import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/action_launcher.dart';
import '../core/notification_service.dart';
import '../data/ai/insight_ai.dart';
import '../data/ai/openrouter_ai.dart';
import '../data/mail/gmail_auth.dart';
import '../data/mail/gmail_source.dart';
import '../data/mail/mail_source.dart';
import '../data/store/insight_store.dart';
import '../data/sync/sync_engine.dart';
import '../domain/actions.dart';
import '../domain/backfill_stats.dart';
import '../domain/models.dart';

enum AppPhase { booting, signedOut, syncing, ready }

/// Thin orchestrator: owns phase + snapshot, delegates work to [SyncEngine].
class AppController extends ChangeNotifier {
  final GmailAuth _auth;
  final InsightStore _store;
  final InsightAi _ai;
  final NotificationService _notifications;

  AppController({
    GmailAuth? auth,
    InsightStore? store,
    InsightAi? ai,
    NotificationService? notifications,
  })  : _auth = auth ?? GmailAuth(),
        _store = store ?? InsightStore(),
        _ai = ai ?? OpenRouterAi(),
        _notifications = notifications ?? NotificationService();

  AppPhase _phase = AppPhase.booting;
  InsightSnapshot _snapshot = const InsightSnapshot();
  bool _isDemo = false;
  String? _error;

  // The first sync that turns an empty snapshot into a populated one gets a
  // celebration card ("here's what was hiding in your inbox"). Booting with a
  // cached snapshot doesn't count — that user has already seen their data.
  bool _hadInsights = false;
  bool _showMoneyShot = false;

  AppPhase get phase => _phase;
  InsightSnapshot get snapshot => _snapshot;
  bool get isDemo => _isDemo;
  bool get isOAuthConfigured => _auth.isConfigured;
  String get aiLabel => _ai.label;
  String? get error => _error;
  String? get accountEmail =>
      _isDemo ? 'demo@nomail.app' : _auth.account?.email;
  String? get accountName =>
      _isDemo ? 'Demo' : _auth.account?.displayName ?? _auth.account?.email;

  bool get showMoneyShot => _showMoneyShot;
  BackfillStats get backfillStats => BackfillStats.fromSnapshot(_snapshot);

  void dismissMoneyShot() {
    _showMoneyShot = false;
    notifyListeners();
  }

  SyncEngine _engine(MailSource source, {InsightAi? ai}) =>
      SyncEngine(source: source, ai: ai ?? _ai, store: _store);

  /// App start: render the cached snapshot instantly, resume the Google
  /// session silently, then refresh in the background.
  Future<void> init() async {
    final cached = await _store.load();
    if (cached != null && !cached.isEmpty) _snapshot = cached;
    _hadInsights = !_snapshot.isEmpty;

    // Not awaited: the iOS permission dialog must float over a live app,
    // not hold boot (and sign-in) hostage until it's answered.
    unawaited(_notifications.init(onTap: _onNotificationTap));

    final resumed = await _auth.resumeSilently();
    if (resumed) {
      _phase = AppPhase.ready;
      notifyListeners();
      await sync();
    } else {
      _phase = AppPhase.signedOut;
      notifyListeners();
    }
  }

  Future<void> signIn() async {
    _error = null;
    _phase = AppPhase.syncing;
    notifyListeners();

    final ok = await _auth.signIn();
    if (!ok) {
      _phase = AppPhase.signedOut;
      _error = _auth.isConfigured
          ? 'Google sign-in was cancelled or failed.'
          : 'Google OAuth is not configured (missing GOOGLE_CLIENT_ID).';
      notifyListeners();
      return;
    }

    _isDemo = false;
    await sync();
  }

  /// Demo runs the real pipeline over fixture emails — same extractors,
  /// same brief builder, no network.
  Future<void> enterDemo() async {
    _isDemo = true;
    _error = null;
    _phase = AppPhase.syncing;
    notifyListeners();

    _snapshot = await _engine(DemoMailSource(), ai: const NoAi()).run();
    _afterSnapshotUpdate();
    _phase = AppPhase.ready;
    notifyListeners();
  }

  Future<void> sync() async {
    if (_isDemo) {
      _snapshot = await _engine(DemoMailSource(), ai: const NoAi()).run();
      _afterSnapshotUpdate();
      notifyListeners();
      return;
    }
    final api = _auth.api;
    if (api == null) return;

    _phase = AppPhase.syncing;
    notifyListeners();

    try {
      _snapshot = await _engine(GmailSource(api)).run(previous: _snapshot);
      _error = null;
      _afterSnapshotUpdate();
    } catch (e) {
      _error = 'Sync failed: $e';
    }

    _phase = AppPhase.ready;
    notifyListeners();
  }

  /// Runs after every successful sync: fire the first-data celebration and
  /// keep tomorrow's 8am brief notification carrying today's content.
  void _afterSnapshotUpdate() {
    if (!_hadInsights && !_snapshot.isEmpty) {
      _hadInsights = true;
      _showMoneyShot = true;
    }
    final brief = _snapshot.brief;
    if (brief != null) {
      // Fire-and-forget: scheduling silently no-ops without permission.
      _notifications.scheduleDailyBrief(brief);
    }
  }

  /// Notification taps: action buttons carry `action:<id>|<uri>` (the uri is
  /// the insight's deep link); everything else just brings the app forward.
  void _onNotificationTap(String payload) {
    if (!payload.startsWith('action:')) return;
    final separator = payload.indexOf('|');
    if (separator < 0) return;
    final uri = Uri.tryParse(payload.substring(separator + 1));
    if (uri == null) return;
    openAction(
      InsightAction(label: '', uri: uri, kind: ActionKind.openLink),
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _store.clear();
    _snapshot = const InsightSnapshot();
    _isDemo = false;
    _error = null;
    _phase = AppPhase.signedOut;
    notifyListeners();
  }
}
