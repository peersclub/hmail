import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/action_launcher.dart';
import '../core/notification_service.dart';
import '../data/ai/ai_status.dart';
import '../data/ai/insight_ai.dart';
import '../data/ai/knowledge_learner.dart';
import '../data/ai/openrouter_ai.dart';
import '../data/mail/gmail_auth.dart';
import '../data/mail/mail_source.dart';
import '../data/mail/multi_gmail_source.dart';
import '../data/store/insight_store.dart';
import '../data/store/knowledge_store.dart';
import '../data/store/settings_store.dart';
import '../data/sync/sync_engine.dart';
import '../domain/actions.dart';
import '../domain/backfill_stats.dart';
import '../domain/knowledge.dart';
import '../domain/models.dart';
import '../domain/scan_settings.dart';
import '../domain/sync_report.dart';

enum AppPhase { booting, signedOut, syncing, ready }

/// Thin orchestrator: owns phase + snapshot, delegates work to [SyncEngine].
class AppController extends ChangeNotifier {
  final GmailAuth _auth;
  final InsightStore _store;
  final InsightAi _ai;
  final NotificationService _notifications;
  final SettingsStore _settingsStore;
  final KnowledgeStore _knowledgeStore;
  final KnowledgeLearner _learner;
  final AiStatusService aiStatus;

  AppController({
    GmailAuth? auth,
    InsightStore? store,
    InsightAi? ai,
    NotificationService? notifications,
    SettingsStore? settingsStore,
    AiStatusService? aiStatusService,
    KnowledgeStore? knowledgeStore,
    KnowledgeLearner? learner,
  })  : _auth = auth ?? GmailAuth(),
        _store = store ?? InsightStore(),
        _ai = ai ?? OpenRouterAi(),
        _notifications = notifications ?? NotificationService(),
        _settingsStore = settingsStore ?? SettingsStore(),
        _knowledgeStore = knowledgeStore ?? KnowledgeStore(),
        _learner = learner ?? KnowledgeLearner(),
        aiStatus = aiStatusService ?? AiStatusService();

  AppPhase _phase = AppPhase.booting;
  InsightSnapshot _snapshot = const InsightSnapshot();
  bool _isDemo = false;
  String? _error;

  // The first sync that turns an empty snapshot into a populated one gets a
  // celebration card ("here's what was hiding in your inbox"). Booting with a
  // cached snapshot doesn't count — that user has already seen their data.
  bool _hadInsights = false;
  bool _showMoneyShot = false;

  ScanSettings _settings = const ScanSettings();
  SyncReport _lastReport = SyncReport.empty();
  SyncStage _stage = SyncStage.idle;

  Playbook _playbook = Playbook.empty;

  /// Everything the app has taught itself, newest recipes last.
  Playbook get playbook => _playbook;

  ScanSettings get settings => _settings;
  SyncReport get lastReport => _lastReport;

  /// What the pipeline is doing right now — drives the live Settings row.
  SyncStage get stage => _stage;

  AppPhase get phase => _phase;
  InsightSnapshot get snapshot => _snapshot;
  bool get isDemo => _isDemo;
  bool get isOAuthConfigured => _auth.isConfigured;
  String get aiLabel => _ai.label;
  String? get error => _error;
  String? get accountEmail =>
      _isDemo ? 'demo@nomail.app' : _auth.first?.email;
  String? get accountName =>
      _isDemo ? 'Demo' : _auth.first?.name;

  /// Every connected Gmail account, for the Settings Accounts section. Empty in
  /// demo mode (the UI renders a read-only demo row instead).
  List<({String email, String? name, String? photoUrl})> get accounts =>
      _isDemo
          ? const []
          : _auth.accounts;

  bool get hasAccounts => _auth.hasAccounts;

  bool get showMoneyShot => _showMoneyShot;
  BackfillStats get backfillStats => BackfillStats.fromSnapshot(_snapshot);

  void dismissMoneyShot() {
    _showMoneyShot = false;
    notifyListeners();
  }

  /// Switching a recipe off keeps it in the playbook, so the learner won't
  /// pay to rediscover something the user rejected.
  Future<void> setKnowledgeEnabled(String id, bool enabled) async {
    _playbook = _playbook.setEnabled(id, enabled);
    notifyListeners();
    await _knowledgeStore.save(_playbook);
  }

  Future<void> forgetKnowledge(String id) async {
    _playbook = _playbook.remove(id);
    notifyListeners();
    await _knowledgeStore.save(_playbook);
  }

  /// Persists [next] and re-schedules the brief if its hour moved. Scan-scope
  /// changes only take effect on the following sync — silently re-scanning
  /// on every toggle would burn the user's API quota.
  Future<void> updateSettings(ScanSettings next) async {
    final previous = _settings;
    _settings = next;
    notifyListeners();
    await _settingsStore.save(next);

    final brief = _snapshot.brief;
    if (brief != null && next.briefHour != previous.briefHour) {
      await _notifications.scheduleDailyBrief(brief, hour: next.briefHour);
    }
  }

  SyncEngine _engine(MailSource source, {InsightAi? ai}) =>
      SyncEngine(source: source, ai: ai ?? _ai, store: _store);

  /// App start: render the cached snapshot instantly, resume the Google
  /// session silently, then refresh in the background.
  Future<void> init() async {
    _settings = await _settingsStore.load();
    _playbook = await _knowledgeStore.load();
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
    final apis = _auth.apis;
    if (apis.isEmpty) return;

    _phase = AppPhase.syncing;
    notifyListeners();

    try {
      final result =
          await _engine(MultiGmailSource(apis, settings: _settings))
              .runReported(
        previous: _snapshot,
        settings: _settings,
        playbook: _playbook,
        learner: _learner,
        onStage: (stage) {
          _stage = stage;
          notifyListeners();
        },
      );
      _snapshot = result.snapshot;
      _lastReport = result.report;
      if (result.playbook.length != _playbook.length) {
        _playbook = result.playbook;
        await _knowledgeStore.save(_playbook);
      }
      _error = null;
      _afterSnapshotUpdate();
    } catch (e) {
      _error = 'Sync failed: $e';
      _lastReport = _lastReport.copyWith(stage: SyncStage.failed);
    }

    _stage = _error == null ? SyncStage.done : SyncStage.failed;
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
      _notifications.scheduleDailyBrief(brief, hour: _settings.briefHour);
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

  /// Throws away every cached insight and re-extracts from Gmail. The normal
  /// sync merges onto what's already there, so this is the escape hatch when
  /// the stored data itself is wrong.
  Future<void> rescan() async {
    await _store.clear();
    _snapshot = const InsightSnapshot();
    _hadInsights = false;
    notifyListeners();
    await sync();
  }

  /// Connects an additional Gmail account, then merges its mail into the
  /// existing snapshot on the next sync. No-ops in demo mode.
  Future<void> addAccount() async {
    if (_isDemo) return;
    _error = null;
    final ok = await _auth.addAccount();
    if (!ok) {
      _error = _auth.isConfigured
          ? 'Adding the account was cancelled or failed.'
          : 'Google OAuth is not configured (missing GOOGLE_CLIENT_ID).';
      notifyListeners();
      return;
    }
    await sync();
  }

  /// Disconnects [email]. Re-syncs from the remaining accounts, or signs the
  /// user out entirely when the last account is removed.
  Future<void> removeAccount(String email) async {
    if (_isDemo) return;
    await _auth.removeAccount(email);
    if (!_auth.hasAccounts) {
      await signOut();
      return;
    }
    await rescan();
  }

  Future<void> signOut() async {
    await _auth.signOutAll();
    await _store.clear();
    _snapshot = const InsightSnapshot();
    _isDemo = false;
    _error = null;
    _phase = AppPhase.signedOut;
    notifyListeners();
  }
}
