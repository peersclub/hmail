/// Insights survive a sign-out, and only for the person they belong to.
///
/// Sign-out used to wipe the snapshot, which cost a full rescan on the way back
/// in — and cost data outright, because the scan windows are capped per domain
/// and price history is derived by diffing two snapshots. Keeping the data is
/// only safe if a different account can never see it, so the two halves are
/// pinned together here: it comes back for the same accounts, and it does not
/// come back for anyone else.
library;

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/domain/account_scope.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A snapshot with one bill per account index named in [accounts].
InsightSnapshot snapshotFor(List<int> accounts) => InsightSnapshot(
      bills: [
        for (final i in accounts)
          Bill(
            issuer: 'Issuer $i',
            amount: 100 + i.toDouble(),
            currency: 'INR',
            lastSeen: DateTime(2026, 8, 1),
            sourceEmailId: 'a$i:msg$i',
          ),
      ],
      lastSyncedAt: DateTime(2026, 8, 1),
    );

List<String> issuersOf(InsightSnapshot s) =>
    [for (final b in s.bills) b.issuer];

List<String> idsOf(InsightSnapshot s) =>
    [for (final b in s.bills) b.sourceEmailId];

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('scopeSnapshot', () {
    Map<String, dynamic> json(List<int> accounts) =>
        snapshotFor(accounts).toJson();

    test('same accounts in the same order restores verbatim', () {
      final result = scopeSnapshot(json([0, 1]),
          saved: ['a@x.com', 'b@y.com'], live: ['a@x.com', 'b@y.com']);
      expect(result!.verdict.scope, AccountScope.identical);
      expect(result.verdict.droppedInsights, 0);
      expect(idsOf(InsightSnapshot.fromJson(result.json)),
          ['a0:msg0', 'a1:msg1']);
    });

    test('reordered accounts have their indices rewritten', () {
      // The failure this prevents is not cosmetic: `a0:` would now name a
      // different inbox, so every "Open email" and every reader fetch would
      // pull from the wrong account.
      final result = scopeSnapshot(json([0, 1]),
          saved: ['a@x.com', 'b@y.com'], live: ['b@y.com', 'a@x.com']);
      expect(result!.verdict.scope, AccountScope.remapped);
      expect(idsOf(InsightSnapshot.fromJson(result.json)),
          ['a1:msg0', 'a0:msg1'],
          reason: 'a@x.com moved to slot 1, b@y.com to slot 0');
    });

    test('a disconnected account takes its insights with it', () {
      final result = scopeSnapshot(json([0, 1]),
          saved: ['a@x.com', 'b@y.com'], live: ['b@y.com']);
      expect(result!.verdict.scope, AccountScope.remapped);
      expect(result.verdict.droppedInsights, 1);
      final restored = InsightSnapshot.fromJson(result.json);
      expect(issuersOf(restored), ['Issuer 1']);
      expect(idsOf(restored), ['a0:msg1'], reason: 'b@y.com is slot 0 now');
    });

    test('a completely different account gets nothing', () {
      expect(
        scopeSnapshot(json([0]),
            saved: ['a@x.com'], live: ['stranger@z.com']),
        isNull,
      );
    });

    test('no saved account list means a pre-scoping snapshot, kept as is', () {
      // Upgrade path. Deleting a user's history because the old format didn't
      // record an owner would be the worse of the two readings.
      final result =
          scopeSnapshot(json([0]), saved: const [], live: ['a@x.com']);
      expect(result!.verdict.scope, AccountScope.identical);
      expect(idsOf(InsightSnapshot.fromJson(result.json)), ['a0:msg0']);
    });

    test('unprefixed ids are never rewritten', () {
      // Demo fixtures and single-account snapshots from before prefixing.
      // Inventing an index for them would fabricate an account.
      final bare = InsightSnapshot(
        bills: [
          Bill(
            issuer: 'Legacy',
            amount: 1,
            currency: 'INR',
            lastSeen: DateTime(2026, 8, 1),
            sourceEmailId: 'demo-netflix',
          ),
        ],
      ).toJson();
      final result = scopeSnapshot(bare,
          saved: ['a@x.com', 'b@y.com'], live: ['b@y.com', 'a@x.com']);
      expect(idsOf(InsightSnapshot.fromJson(result!.json)), ['demo-netflix']);
    });

    test('scalar and object fields survive the walk untouched', () {
      // The walk only rewrites list entries; `brief`, `lastSyncedAt` and
      // `emailsScanned` must arrive unchanged or a restore silently loses the
      // last-synced time and the daily brief.
      final full = InsightSnapshot(
        bills: snapshotFor([0]).bills,
        brief: DailyBrief(
          headline: 'Three things',
          bullets: const ['one', 'two'],
          generatedAt: DateTime(2026, 8, 1),
        ),
        lastSyncedAt: DateTime(2026, 8, 1, 9, 30),
        emailsScanned: 412,
      ).toJson();
      final result =
          scopeSnapshot(full, saved: ['a@x.com'], live: ['a@x.com']);
      final restored = InsightSnapshot.fromJson(result!.json);
      expect(restored.brief!.headline, 'Three things');
      expect(restored.lastSyncedAt, DateTime(2026, 8, 1, 9, 30));
      expect(restored.emailsScanned, 412);
    });
  });

  group('InsightStore scoping', () {
    test('the same account gets its snapshot back', () async {
      await InsightStore().save(snapshotFor([0]), accounts: ['a@x.com']);
      final loaded = await InsightStore().load(accounts: ['a@x.com']);
      expect(issuersOf(loaded!), ['Issuer 0']);
    });

    test('signed out, nothing is handed back', () async {
      // The signed-out screens must not render the last session's data, and
      // with no live list there is no way to know whose the stored copy is.
      await InsightStore().save(snapshotFor([0]), accounts: ['a@x.com']);
      expect(await InsightStore().load(), isNull);
      expect(await InsightStore().load(accounts: const []), isNull);
    });

    test('a different account on the same phone sees nothing', () async {
      await InsightStore().save(snapshotFor([0]), accounts: ['a@x.com']);
      expect(await InsightStore().load(accounts: ['stranger@z.com']), isNull);
    });

    test('an unscoped save is readable by anyone — demo and tests', () async {
      await InsightStore().save(snapshotFor([0]));
      expect(await InsightStore().load(accounts: ['anyone@z.com']), isNotNull);
      expect(await InsightStore().load(), isNotNull);
    });

    test('a legacy bare snapshot is migrated rather than dropped', () async {
      // v9/v10 stored the snapshot with no wrapper and no owner. Reading it is
      // the difference between an upgrade and a data loss.
      for (final key in ['insight_snapshot_v9', 'insight_snapshot_v10']) {
        SharedPreferences.setMockInitialValues(
            {key: jsonEncode(snapshotFor([0]).toJson())});
        final loaded = await InsightStore().load(accounts: ['a@x.com']);
        expect(issuersOf(loaded!), ['Issuer 0'], reason: 'from $key');
      }
    });

    test('saving forward removes the legacy copies', () async {
      SharedPreferences.setMockInitialValues({
        'insight_snapshot_v9': jsonEncode(snapshotFor([0]).toJson()),
        'insight_snapshot_v10': jsonEncode(snapshotFor([0]).toJson()),
      });
      await InsightStore().save(snapshotFor([1]), accounts: ['b@y.com']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('insight_snapshot_v9'), isNull);
      expect(prefs.getString('insight_snapshot_v10'), isNull);
      expect(prefs.getString('insight_snapshot_v11'), isNotNull);
    });

    test('a corrupt record degrades to null, not a crash', () async {
      SharedPreferences.setMockInitialValues(
          {'insight_snapshot_v11': 'not json'});
      expect(await InsightStore().load(accounts: ['a@x.com']), isNull);
    });

    test('loadScoped reports a partial restore', () async {
      await InsightStore()
          .save(snapshotFor([0, 1]), accounts: ['a@x.com', 'b@y.com']);
      final scoped = await InsightStore().loadScoped(accounts: ['a@x.com']);
      expect(scoped!.verdict.droppedInsights, 1);
      expect(issuersOf(scoped.snapshot), ['Issuer 0']);
    });
  });

  group('sign-out keeps the data on disk', () {
    test('signOut leaves the stored snapshot alone', () async {
      await InsightStore().save(snapshotFor([0]), accounts: ['a@x.com']);
      final app = AppController();
      await app.init();
      await app.signOut();

      // Cleared from memory so the signed-out screens are empty…
      expect(app.snapshot.isEmpty, isTrue);
      // …but still on disk, waiting for that account to come back.
      expect(await InsightStore().load(accounts: ['a@x.com']), isNotNull);
    });

    test('deleteLocalData is the one that erases', () async {
      await InsightStore().save(snapshotFor([0]), accounts: ['a@x.com']);
      final app = AppController();
      await app.init();
      await app.deleteLocalData();

      expect(await InsightStore().load(accounts: ['a@x.com']), isNull);
      expect(app.snapshot.isEmpty, isTrue);
    });

    test('demo fixtures never restore into a real session', () async {
      // Demo runs the real pipeline, so it writes to the real store. Once a
      // snapshot outlives its session that becomes a leak unless demo data has
      // an owner no real account can match: otherwise demo → exit → sign in
      // would hand someone Netflix-and-BESCOM fixtures as their own insights.
      final app = AppController();
      await app.init();
      await app.enterDemo();
      expect(app.snapshot.isEmpty, isFalse, reason: 'demo produced data');

      expect(await InsightStore().load(accounts: ['real@gmail.com']), isNull);
      expect(await InsightStore().load(accounts: const []), isNull);
    });

    test('booting signed out shows nothing even though data exists', () async {
      // init() cannot resume a session in a test, so this is the signed-out
      // boot: the snapshot is on disk and must stay invisible.
      await InsightStore().save(snapshotFor([0]), accounts: ['a@x.com']);
      final app = AppController();
      await app.init();
      expect(app.snapshot.isEmpty, isTrue);
      expect(await InsightStore().load(accounts: ['a@x.com']), isNotNull);
    });
  });
}
