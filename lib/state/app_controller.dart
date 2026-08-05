import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/action_launcher.dart';
import '../core/ai_key.dart';
import '../core/notification_service.dart';
import '../core/upcoming_alerts.dart';
import '../ui/action_sheet.dart' show installedApps;
import '../data/ai/ai_status.dart';
import '../data/ai/insight_ai.dart';
import '../data/ai/knowledge_learner.dart';
import '../data/ai/openrouter_ai.dart';
import '../data/backup/backup_service.dart';
import '../data/backup/backup_target.dart';
import '../data/backup/drive_backup_target.dart';
import '../data/backup/icloud_backup_target.dart';
import '../data/mail/gmail_auth.dart';
import '../data/mail/mail_source.dart';
import '../data/mail/multi_gmail_source.dart';
import '../data/store/accounts_store.dart';
import '../data/store/backup_prefs_store.dart';
import '../data/store/insight_store.dart';
import '../data/store/knowledge_store.dart';
import '../data/store/link_feedback_store.dart';
import '../data/store/settings_store.dart';
import '../data/store/timeline_order_store.dart';
import '../data/sync/sync_engine.dart';
import '../domain/actions.dart';
import '../domain/backfill_stats.dart';
import '../domain/backup_bundle.dart';
import '../domain/backup_prefs.dart';
import '../domain/knowledge.dart';
import '../domain/link_feedback.dart';
import '../domain/models.dart';
import '../domain/scan_settings.dart';
import '../domain/sync_report.dart';

enum AppPhase { booting, signedOut, syncing, ready }

/// What the backup subsystem is doing right now — drives inline progress on
/// the Backup screen (never a modal, never a footnote far from the action).
enum BackupActivity { idle, backingUp, checking, restoring }

/// Which action an error belongs to, so the message renders directly under
/// the control the user actually tapped.
enum BackupErrorScope { backup, restore }

/// Thin orchestrator: owns phase + snapshot, delegates work to [SyncEngine].
class AppController extends ChangeNotifier {
  final GmailAuth _auth;
  final InsightStore _store;
  final InsightAi _ai;
  final NotificationService _notifications;
  final SettingsStore _settingsStore;
  final KnowledgeStore _knowledgeStore;
  final LinkFeedbackStore _feedbackStore;
  final KnowledgeLearner _learner;
  final AiStatusService aiStatus;

  /// Backup service reads/writes the same SharedPreferences-backed stores the
  /// app uses — the store classes are stateless key wrappers, so fresh
  /// instances see the same data.
  final BackupService _backup = BackupService(
    insights: InsightStore(),
    knowledge: KnowledgeStore(),
    settings: SettingsStore(),
    timeline: TimelineOrderStore(),
  );
  final BackupPrefsStore _backupPrefsStore = BackupPrefsStore();
  final AccountsStore _accountsStore = AccountsStore();

  /// Accounts remembered across launches (see [accounts]).
  List<StoredAccount> _knownAccounts = [];
  Map<String, String> _accountSyncIssues = const {};
  String? _accountsNotice;
  String? _accountsError;
  final Map<String, BackupTarget>? _backupTargetsOverride;
  late final Map<String, BackupTarget> _backupTargets =
      _backupTargetsOverride ??
          {
            'gdrive': DriveBackupTarget(
              signedIn: () async => !_isDemo && _auth.hasAccounts,
              connect: _auth.driveApi,
            ),
            'icloud': const ICloudBackupTarget(),
          };

  AppController({
    GmailAuth? auth,
    InsightStore? store,
    InsightAi? ai,
    NotificationService? notifications,
    SettingsStore? settingsStore,
    AiStatusService? aiStatusService,
    KnowledgeStore? knowledgeStore,
    LinkFeedbackStore? feedbackStore,
    KnowledgeLearner? learner,
    Map<String, BackupTarget>? backupTargets,
  })  : _backupTargetsOverride = backupTargets,
        _auth = auth ?? GmailAuth(),
        _store = store ?? InsightStore(),
        _ai = ai ?? OpenRouterAi(),
        _notifications = notifications ?? NotificationService(),
        _settingsStore = settingsStore ?? SettingsStore(),
        _knowledgeStore = knowledgeStore ?? KnowledgeStore(),
        _feedbackStore = feedbackStore ?? LinkFeedbackStore(),
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

  LinkFeedbackLog _feedback = const LinkFeedbackLog();

  /// Which learned recipes have produced links the user reported as wrong.
  /// Surfaced in the Knowledge screen so a bad template is visible rather
  /// than quietly wasting taps.
  List<String> get suspectKnowledge => _feedback.suspectKnowledgeTypes;

  /// Records how a link turned out. The signal is worth persisting even
  /// though nothing acts on it automatically yet — deleting a recipe is the
  /// user's call, not ours.
  Future<void> recordLinkFeedback(LinkFeedback feedback) async {
    _feedback = _feedback.add(feedback);
    notifyListeners();
    await _feedbackStore.save(_feedback);
  }

  Playbook _playbook = Playbook.empty;

  /// Everything the app has taught itself, newest recipes last.
  Playbook get playbook => _playbook;

  ScanSettings get settings => _settings;
  SyncReport get lastReport => _lastReport;

  /// What the pipeline is doing right now — drives the live Settings row.
  SyncStage get stage => _stage;

  String? _stageDetail;

  /// The specific thing happening inside [stage] ("Reading packages · 15 of
  /// 50"). Null between syncs.
  String? get stageDetail => _stageDetail;

  /// One line for the header: the detail when there is one, else the stage.
  String get activityLine => _stageDetail ?? _stage.label;

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

  /// Accounts NoMail knows about, live ones first. `connected: false` marks a
  /// remembered account whose session didn't survive the restart —
  /// google_sign_in 7.x only silently restores the platform's single active
  /// session, so every other stored account boots into a reconnect state
  /// instead of silently vanishing from the list.
  List<({String email, String? name, String? photoUrl, bool connected})>
      get accounts {
    if (_isDemo) return const [];
    final live = _auth.accounts;
    final liveEmails = {for (final a in live) a.email};
    return [
      for (final a in live)
        (email: a.email, name: a.name, photoUrl: a.photoUrl, connected: true),
      for (final s in _knownAccounts)
        if (!liveEmails.contains(s.email))
          (
            email: s.email,
            name: s.name,
            photoUrl: s.photoUrl,
            connected: false,
          ),
    ];
  }

  bool get hasAccounts => _auth.hasAccounts;

  /// Per-account trouble from the last sync (email → short reason). Rebuilt
  /// on every sync; empty when every inbox read cleanly.
  Map<String, String> get accountSyncIssues => _accountSyncIssues;

  /// In-flow result lines for the Accounts section — same scoped-feedback
  /// pattern as backup: the message renders under the control that caused it.
  String? get accountsNotice => _accountsNotice;
  String? get accountsError => _accountsError;

  /// Which account an insight came from, for attribution when several
  /// inboxes are merged. Accepts either a bare source-email id or a full
  /// insight id ('bill:a1:xyz'); returns null when only one (or no) account
  /// is connected — attribution is noise until inboxes can be confused.
  String? accountForInsight(String id) {
    final live = _auth.accounts;
    if (_isDemo || live.length < 2) return null;
    final m = RegExp(r'(?:^|:)a(\d+):').firstMatch(id);
    if (m == null) return null;
    final index = int.parse(m.group(1)!);
    return index < live.length ? live[index].email : null;
  }

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

  // ── Backup ────────────────────────────────────────────────────────────
  BackupPrefs _backupPrefs = const BackupPrefs();
  BackupActivity _backupActivity = BackupActivity.idle;
  String? _backupError;
  BackupErrorScope? _backupErrorScope;
  String? _backupNotice;
  BackupErrorScope? _backupNoticeScope;
  BackupMeta? _remoteBackupMeta;
  bool _remoteMetaChecked = false;
  BackupBundle? _restoreCandidate;

  BackupPrefs get backupPrefs => _backupPrefs;
  BackupActivity get backupActivity => _backupActivity;
  bool get backupBusy => _backupActivity != BackupActivity.idle;

  /// Failure message for the *last* backup action, with the scope naming the
  /// control it belongs under. Cleared when a new action starts.
  String? get backupError => _backupError;
  BackupErrorScope? get backupErrorScope => _backupErrorScope;

  /// In-flow success line ("Backed up · 12 KB"), scoped like errors.
  String? get backupNotice => _backupNotice;
  BackupErrorScope? get backupNoticeScope => _backupNoticeScope;

  /// Metadata of the backup currently in the cloud, once [refreshRemoteMeta]
  /// has run. Null means "none found" or "not checked yet" — disambiguate with
  /// [remoteMetaChecked].
  BackupMeta? get remoteBackupMeta => _remoteBackupMeta;
  bool get remoteMetaChecked => _remoteMetaChecked;

  /// The downloaded bundle awaiting the user's restore confirmation.
  BackupBundle? get restoreCandidate => _restoreCandidate;

  List<BackupTarget> get backupTargets => _backupTargets.values.toList();

  BackupTarget get _selectedTarget =>
      _backupTargets[_backupPrefs.destinationId] ?? _backupTargets.values.first;

  String get backupDestinationLabel => _selectedTarget.label;

  String _deviceLabel() => accountName ?? accountEmail ?? 'This device';

  void _startBackupAction(BackupActivity activity) {
    _backupActivity = activity;
    _backupError = null;
    _backupErrorScope = null;
    _backupNotice = null;
    _backupNoticeScope = null;
    notifyListeners();
  }

  void _finishBackupAction({
    String? error,
    String? notice,
    required BackupErrorScope scope,
  }) {
    _backupActivity = BackupActivity.idle;
    _backupError = error;
    _backupErrorScope = error == null ? null : scope;
    _backupNotice = notice;
    _backupNoticeScope = notice == null ? null : scope;
    notifyListeners();
  }

  Future<bool> backupTargetAvailable(String id) async {
    final t = _backupTargets[id];
    if (t == null) return false;
    try {
      return await t.isAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<void> setBackupDestination(String id) async {
    if (!_backupTargets.containsKey(id)) return;
    _backupPrefs = _backupPrefs.copyWith(destinationId: id);
    _remoteBackupMeta = null;
    _remoteMetaChecked = false;
    _backupError = null;
    _backupNotice = null;
    notifyListeners();
    await _backupPrefsStore.save(_backupPrefs);
    unawaited(refreshRemoteMeta());
  }

  Future<void> setBackupFrequency(BackupFrequency frequency) async {
    _backupPrefs = _backupPrefs.copyWith(frequency: frequency);
    notifyListeners();
    await _backupPrefsStore.save(_backupPrefs);
  }

  /// Manual "Back Up Now". On success the status card and inline notice update
  /// in place; on failure [backupError] carries the reason + recovery and
  /// renders directly under the button. Returns true on success.
  Future<bool> backUpNow() async {
    if (backupBusy || _isDemo) return false;
    _startBackupAction(BackupActivity.backingUp);
    try {
      final meta = await _backup.backUpTo(
        _selectedTarget,
        deviceLabel: _deviceLabel(),
        accountEmail: accountEmail,
      );
      _backupPrefs = _backupPrefs.copyWith(lastBackupAt: meta.createdAt);
      _remoteBackupMeta = meta;
      _remoteMetaChecked = true;
      await _backupPrefsStore.save(_backupPrefs);
      _finishBackupAction(
        notice: 'Backed up · ${_formatSize(meta.sizeBytes)}',
        scope: BackupErrorScope.backup,
      );
      return true;
    } on BackupException catch (e) {
      _finishBackupAction(error: e.message, scope: BackupErrorScope.backup);
      return false;
    } catch (e) {
      _finishBackupAction(
        error: 'Something unexpected went wrong. Try again.',
        scope: BackupErrorScope.backup,
      );
      return false;
    }
  }

  /// Step 1 of restore: fetch the newest backup (may show the Google consent
  /// sheet — the user explicitly asked). On success the bundle is held as
  /// [restoreCandidate] for the UI to confirm; nothing is applied yet.
  Future<BackupMeta?> prepareRestore() async {
    if (backupBusy || _isDemo) return null;
    _startBackupAction(BackupActivity.checking);
    try {
      final bundle = await _selectedTarget.download();
      if (bundle == null) {
        _finishBackupAction(
          error: 'No backup found in ${_selectedTarget.label} for '
              '${accountEmail ?? 'this account'}.',
          scope: BackupErrorScope.restore,
        );
        return null;
      }
      _restoreCandidate = bundle;
      final meta = BackupMeta.of(bundle);
      _remoteBackupMeta = meta;
      _remoteMetaChecked = true;
      _finishBackupAction(scope: BackupErrorScope.restore);
      return meta;
    } on BackupException catch (e) {
      _finishBackupAction(error: e.message, scope: BackupErrorScope.restore);
      return null;
    } catch (e) {
      _finishBackupAction(
        error: 'Something unexpected went wrong. Try again.',
        scope: BackupErrorScope.restore,
      );
      return null;
    }
  }

  /// Step 2: the user confirmed — apply the held bundle and reload the app's
  /// in-memory state so every screen reflects the restored data at once.
  Future<RestoreOutcome?> confirmRestore() async {
    final bundle = _restoreCandidate;
    if (bundle == null || backupBusy) return null;
    _startBackupAction(BackupActivity.restoring);
    try {
      final outcome = await _backup.restore(bundle);
      _restoreCandidate = null;
      await _reloadFromStores();
      _finishBackupAction(
        notice: _restoreNotice(outcome),
        scope: BackupErrorScope.restore,
      );
      return outcome;
    } catch (e) {
      _finishBackupAction(
        error: 'Restore didn\'t complete. Your existing data is untouched — '
            'try again.',
        scope: BackupErrorScope.restore,
      );
      return null;
    }
  }

  void cancelRestore() {
    _restoreCandidate = null;
    notifyListeners();
  }

  static String _restoreNotice(RestoreOutcome o) {
    final parts = <String>[
      '${o.insightCount} insight${o.insightCount == 1 ? '' : 's'}',
      if (o.learnedTypeCount > 0)
        '${o.learnedTypeCount} learned type'
            '${o.learnedTypeCount == 1 ? '' : 's'}',
    ];
    return 'Restored ${parts.join(' and ')}';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Reads the destination's backup metadata for the summary card. Silent —
  /// never triggers a consent prompt.
  Future<BackupMeta?> refreshRemoteMeta() async {
    try {
      final target = _selectedTarget;
      if (!await target.isAvailable()) {
        _remoteBackupMeta = null;
        _remoteMetaChecked = true;
        notifyListeners();
        return null;
      }
      _remoteBackupMeta = await target.latest();
    } catch (_) {
      // Metadata is best-effort; a read failure shouldn't break the screen.
    }
    _remoteMetaChecked = true;
    notifyListeners();
    return _remoteBackupMeta;
  }

  /// Fired after a successful sync: backs up opportunistically when the chosen
  /// frequency says one is due. Fully silent — it runs only when the target is
  /// already authorized (never a surprise consent sheet) and swallows failures
  /// (a background backup must never interrupt the sync that triggered it).
  Future<void> _maybeAutoBackup() async {
    if (_isDemo || !_backupPrefs.isDue(DateTime.now())) return;
    final target = _selectedTarget;
    try {
      if (!await target.isAuthorized()) return;
      final meta = await _backup.backUpTo(
        target,
        deviceLabel: _deviceLabel(),
        accountEmail: accountEmail,
      );
      _backupPrefs = _backupPrefs.copyWith(lastBackupAt: meta.createdAt);
      _remoteBackupMeta = meta;
      _remoteMetaChecked = true;
      await _backupPrefsStore.save(_backupPrefs);
      notifyListeners();
    } catch (_) {
      // Best-effort by design.
    }
  }

  Future<void> _reloadFromStores() async {
    _settings = await _settingsStore.load();
    _playbook = await _knowledgeStore.load();
    _feedback = await _feedbackStore.load();
    final snap = await _store.load();
    if (snap != null) {
      _snapshot = snap;
      _hadInsights = !snap.isEmpty;
    }
    notifyListeners();
  }


  SyncEngine _engine(MailSource source, {InsightAi? ai}) =>
      SyncEngine(source: source, ai: ai ?? _ai, store: _store);

  /// App start: render the cached snapshot instantly, resume the Google
  /// session silently, then refresh in the background.
  Future<void> init() async {
    await AiKey.load(); // user-entered key must beat the .env fallback
    _settings = await _settingsStore.load();
    _playbook = await _knowledgeStore.load();
    _backupPrefs = await _backupPrefsStore.load();
    _knownAccounts = await _accountsStore.load();
    final cached = await _store.load();
    if (cached != null && !cached.isEmpty) _snapshot = cached;
    _hadInsights = !_snapshot.isEmpty;

    // Warm the installed-app sweep so the first action sheet is instant and
    // already knows which apps to name.
    unawaited(installedApps.detect());

    // Not awaited: the iOS permission dialog must float over a live app,
    // not hold boot (and sign-in) hostage until it's answered.
    unawaited(_notifications.init(onTap: _onNotificationTap));

    final resumed = await _auth.resumeSilently();
    if (resumed) {
      // The platform restores only its single active session; merge it into
      // the remembered list so every *other* stored account surfaces as a
      // reconnect row rather than silently disappearing.
      await _persistAccounts();
      _phase = AppPhase.ready;
      notifyListeners();
      await sync();
    } else {
      _phase = AppPhase.signedOut;
      notifyListeners();
    }
  }

  /// True while the Google OAuth sheet is (or may be) on screen. The phase
  /// stays [AppPhase.signedOut] during authentication so the router keeps the
  /// sign-in screen mounted — flipping to syncing before auth succeeded used
  /// to flash the empty shell behind the OAuth sheet, then bounce back on
  /// cancel. The sign-in screen shows its progress state off this flag.
  bool _authenticating = false;
  bool get authenticating => _authenticating;

  Future<void> signIn() async {
    _error = null;
    _authenticating = true;
    notifyListeners();

    final ok = await _auth.signIn();
    _authenticating = false;
    if (!ok) {
      _phase = AppPhase.signedOut;
      _error = _auth.isConfigured
          ? 'Google sign-in was cancelled or failed.'
          : 'Google OAuth is not configured (missing GOOGLE_CLIENT_ID).';
      notifyListeners();
      return;
    }

    // Only now does the app leave the sign-in screen — for a real sync.
    _isDemo = false;
    await _persistAccounts();
    _phase = AppPhase.syncing;
    notifyListeners();
    await sync();
  }

  /// Demo runs the real pipeline over fixture emails — same extractors,
  /// same brief builder, no network.
  Future<void> enterDemo() async {
    _isDemo = true;
    _error = null;
    _phase = AppPhase.syncing;
    notifyListeners();

    // A fabricated "last month" snapshot so the price-hike detector has two
    // syncs to diff — see [demoHistory].
    _snapshot = await _engine(DemoMailSource(), ai: const NoAi())
        .run(previous: demoHistory());
    _afterSnapshotUpdate();
    _phase = AppPhase.ready;
    notifyListeners();
  }

  /// The source of the most recent real sync, kept so per-account failures
  /// can be read back after the run.
  MultiGmailSource? _multiSource;

  Future<void> sync() async {
    if (_isDemo) {
      // Re-syncing demo keeps the same fabricated history, so the price change
      // stays put instead of flickering away on a pull-to-refresh.
      _snapshot = await _engine(DemoMailSource(), ai: const NoAi())
          .run(previous: demoHistory());
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
          await _engine(_multiSource = MultiGmailSource(
        apis,
        settings: _settings,
        accountEmails: [for (final a in _auth.accounts) a.email],
      )).runReported(
        previous: _snapshot,
        settings: _settings,
        playbook: _playbook,
        learner: _learner,
        onStage: (stage) {
          _stage = stage;
          notifyListeners();
        },
        onDetail: (detail) {
          _stageDetail = detail;
          notifyListeners();
        },
      );
      _snapshot = result.snapshot;
      _lastReport = result.report;
      if (result.playbook.length != _playbook.length) {
        _playbook = result.playbook;
        await _knowledgeStore.save(_playbook);
      }
      // Surface which inboxes were skipped — a silently failing account is
      // how its insights quietly go stale.
      _accountSyncIssues = {
        for (final f in _multiSource?.lastFailures ?? const [])
          f.account: f.message,
      };
      _error = null;
      _afterSnapshotUpdate();
    } catch (e) {
      _error = 'Sync failed: $e';
      _lastReport = _lastReport.copyWith(stage: SyncStage.failed);
    }

    _stage = _error == null ? SyncStage.done : SyncStage.failed;
    _stageDetail = null;
    _phase = AppPhase.ready;
    notifyListeners();

    // Opportunistic backup after a clean sync, if one is due.
    if (_error == null) unawaited(_maybeAutoBackup());
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
    // Proactive alerts are rebuilt from scratch every sync rather than
    // incrementally maintained: the builder is pure and the scheduler cancels
    // its own namespace first, so a renewal that moved or a bill that got paid
    // simply stops being scheduled. Fire-and-forget for the same reason as the
    // brief — a device that refused notifications must still sync.
    unawaited(_notifications
        .syncUpcomingAlerts(buildUpcomingAlerts(_snapshot, DateTime.now())));
  }

  /// Notification taps: action buttons carry `action:<id>|<uri>` (the uri is
  /// the insight's deep link); everything else just brings the app forward.
  /// Where a notification tap should land inside the app (tab index). The
  /// shell listens and consumes; null = no pending request. This is what
  /// makes the daily-brief notification open Today instead of merely
  /// foregrounding the app.
  final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  void _onNotificationTap(String payload) {
    if (payload == 'brief') {
      tabRequest.value = 0; // Today — the brief's home
      return;
    }
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
    _accountsNotice = null;
    _accountsError = null;
    notifyListeners();

    final result = await _auth.addAccount();
    switch (result) {
      case AddAccountResult.added:
        final added = _auth.accounts.last.email;
        _accountsNotice = 'Connected $added';
        await _persistAccounts();
        notifyListeners();
        await sync();
      case AddAccountResult.alreadyConnected:
        // The platform quirk: iOS re-offered the active account. Explain the
        // way past it instead of pretending nothing happened.
        _accountsNotice =
            'That account is already connected. To add a different Gmail, '
            'pick another account in Google\'s sheet — use "Use another '
            'account" if it isn\'t listed.';
        notifyListeners();
      case AddAccountResult.failed:
        _accountsError = _auth.isConfigured
            ? 'Adding the account was cancelled or failed. Try again.'
            : 'Google OAuth is not configured (missing GOOGLE_CLIENT_ID).';
        notifyListeners();
    }
  }

  /// Reconnects a remembered account whose session didn't survive a restart.
  /// Drives the same Google sheet as adding; succeeds when the user picks
  /// [email] there — picking a different account is still narrated honestly.
  Future<void> reconnectAccount(String email) async {
    if (_isDemo) return;
    _accountsNotice = null;
    _accountsError = null;
    notifyListeners();

    final result = await _auth.addAccount();
    if (result == AddAccountResult.failed) {
      _accountsError = 'Reconnecting was cancelled or failed. Try again.';
      notifyListeners();
      return;
    }
    if (_auth.hasEmail(email)) {
      _accountsNotice = 'Reconnected $email';
      await _persistAccounts();
      notifyListeners();
      await sync();
      return;
    }
    // The Google sheet returned some other account — it's connected now
    // (never throw away a grant), but the one they asked for still isn't.
    final got = _auth.accounts.last.email;
    _accountsNotice =
        'Google connected $got instead. $email still needs reconnecting — '
        'tap it and choose that account in Google\'s sheet.';
    await _persistAccounts();
    notifyListeners();
    await sync();
  }

  /// Merges the live accounts into the remembered list (live data wins,
  /// remembered-but-disconnected entries survive) and persists it.
  Future<void> _persistAccounts() async {
    final live = _auth.accounts;
    final liveEmails = {for (final a in live) a.email};
    _knownAccounts = [
      for (final a in live)
        (email: a.email, name: a.name, photoUrl: a.photoUrl),
      for (final s in _knownAccounts)
        if (!liveEmails.contains(s.email)) s,
    ];
    await _accountsStore.save(_knownAccounts);
  }

  /// Disconnects [email]. Re-syncs from the remaining accounts, or signs the
  /// user out entirely when the last account is removed.
  Future<void> removeAccount(String email) async {
    if (_isDemo) return;
    _accountsNotice = null;
    _accountsError = null;
    await _auth.removeAccount(email);
    // Forget it across launches too, or it would resurrect as "reconnect".
    _knownAccounts =
        [for (final s in _knownAccounts) if (s.email != email) s];
    await _accountsStore.save(_knownAccounts);
    _accountSyncIssues =
        {for (final e in _accountSyncIssues.entries) if (e.key != email) e.key: e.value};
    if (!_auth.hasAccounts && _knownAccounts.isEmpty) {
      await signOut();
      return;
    }
    notifyListeners();
    if (_auth.hasAccounts) await rescan();
  }

  Future<void> signOut() async {
    await _auth.signOutAll();
    await _store.clear();
    await _accountsStore.clear();
    _knownAccounts = [];
    _accountSyncIssues = const {};
    _accountsNotice = null;
    _accountsError = null;
    _snapshot = const InsightSnapshot();
    _isDemo = false;
    _error = null;
    _phase = AppPhase.signedOut;
    notifyListeners();
  }
}
