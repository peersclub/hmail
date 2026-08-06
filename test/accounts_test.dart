/// Multi-account management: accounts must survive restarts (as reconnect
/// rows, given the platform restores only one session), sync failures must
/// name the inbox, and attribution must map prefixed ids to the right email.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/store/accounts_store.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AccountsStore', () {
    test('round-trips stored accounts', () async {
      final store = AccountsStore();
      await store.save([
        (email: 'a@x.com', name: 'A', photoUrl: null),
        (email: 'b@y.com', name: null, photoUrl: 'http://p/b.png'),
      ]);

      final loaded = await AccountsStore().load();
      expect(loaded, hasLength(2));
      expect(loaded.first.email, 'a@x.com');
      expect(loaded.last.photoUrl, 'http://p/b.png');
    });

    test('corrupt payload degrades to empty, not a crash', () async {
      SharedPreferences.setMockInitialValues(
          {'connected_accounts_v1': 'not json'});
      expect(await AccountsStore().load(), isEmpty);
    });
  });

  group('accounts across restarts', () {
    test('remembered accounts surface as disconnected reconnect rows',
        () async {
      // A previous session had connected two accounts…
      await AccountsStore().save([
        (email: 'personal@gmail.com', name: 'Personal', photoUrl: null),
        (email: 'work@gmail.com', name: 'Work', photoUrl: null),
      ]);

      // …but on this boot the platform restores no session (test env).
      final app = AppController();
      await app.init();

      final accounts = app.accounts;
      expect(accounts, hasLength(2),
          reason: 'stored accounts must not silently vanish on restart');
      expect(accounts.every((a) => !a.connected), isTrue,
          reason: 'no live session in tests — both need reconnecting');
      expect(accounts.map((a) => a.email),
          containsAll(['personal@gmail.com', 'work@gmail.com']));
    });

    test('removing a remembered account forgets it for good', () async {
      await AccountsStore().save([
        (email: 'personal@gmail.com', name: 'Personal', photoUrl: null),
        (email: 'work@gmail.com', name: 'Work', photoUrl: null),
      ]);
      final app = AppController();
      await app.init();

      await app.removeAccount('work@gmail.com');

      expect(app.accounts.map((a) => a.email), ['personal@gmail.com']);
      expect((await AccountsStore().load()).map((a) => a.email),
          ['personal@gmail.com'],
          reason: 'the removal must persist, or it resurrects on relaunch');
    });

    test('signOut keeps the remembered accounts on disk', () async {
      // Sign-out ends the session; it does not erase the device. Forgetting
      // the account list here is what used to make signing back in a
      // from-scratch rescan — and a rescan cannot recover what the scan
      // windows exclude, so it was real data loss dressed up as a refresh.
      await AccountsStore().save([
        (email: 'personal@gmail.com', name: 'Personal', photoUrl: null),
      ]);
      final app = AppController();
      await app.init();
      await app.signOut();

      expect(await AccountsStore().load(), hasLength(1),
          reason: 'the account is remembered so it can be reconnected');
    });

    test('deleteLocalData is the one that erases, and it signs out too',
        () async {
      // The destructive intent, now explicit and separate. Mail is untouched;
      // this only removes the derived copy.
      await AccountsStore().save([
        (email: 'personal@gmail.com', name: 'Personal', photoUrl: null),
      ]);
      final app = AppController();
      await app.init();
      await app.deleteLocalData();

      expect(await AccountsStore().load(), isEmpty);
      expect(app.accounts, isEmpty);
      expect(app.snapshot.isEmpty, isTrue);
    });
  });

  group('accountForInsight', () {
    test('is null with fewer than two live accounts (attribution is noise)',
        () async {
      final app = AppController();
      expect(app.accountForInsight('bill:a0:xyz'), isNull);
    });
  });
}
