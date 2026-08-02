import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/core/installed_apps.dart';
import 'package:hmail/domain/app_targets.dart';

/// The only entries allowed to claim `launchFormatVerified: true` — each one
/// carries an official source URL in a comment next to it in
/// `lib/domain/app_targets.dart`. If you flip the flag on a new target, add it
/// here *and* cite the doc, or this test fails.
const _verifiedKeys = <String>{
  'google_pay', // developers.google.com/pay/india/api/android/in-app-payments
  'zoom', // developers.zoom.us launch-zoom-client-from-your-app
  'google_maps', // developers.google.com/maps/documentation/urls/ios-urlscheme
  'uber', // developer.uber.com/docs/deep-linking
  'ola', // developers.olacabs.com/docs/deep-linking
};

void main() {
  group('AppCatalog entries', () {
    test('every target has a non-empty key and name', () {
      for (final target in AppCatalog.all) {
        expect(target.key.trim(), isNotEmpty, reason: 'key on $target');
        expect(target.name.trim(), isNotEmpty, reason: 'name on ${target.key}');
      }
    });

    test('keys are unique', () {
      final keys = AppCatalog.all.map((t) => t.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('probe schemes are unique', () {
      final schemes = AppCatalog.probeSchemes;
      expect(schemes.toSet().length, schemes.length);
    });

    test('probe schemes are bare — no "://" and no colon', () {
      for (final scheme in AppCatalog.probeSchemes) {
        expect(scheme, isNotEmpty);
        expect(scheme.contains(':'), isFalse, reason: scheme);
        expect(scheme, scheme.toLowerCase(), reason: '$scheme must be lower');
      }
    });

    test('scheme count stays within the iOS LSApplicationQueriesSchemes cap',
        () {
      expect(AppCatalog.probeSchemes.length,
          lessThanOrEqualTo(AppCatalog.iosSchemeLimit));
    });

    test('probeUri renders as scheme:// — the form canLaunchUrl needs', () {
      expect(AppCatalog.byKey('delhivery')!.probeUri.toString(),
          'delhivery://');
      // Reverse-DNS schemes survive the round trip too.
      expect(AppCatalog.byKey('amazon')!.probeUri.toString(),
          'com.amazon.mobile.shopping://');
      // Universal-link-only targets have no probe.
      expect(AppCatalog.byKey('google_meet')!.probeUri, isNull);
    });

    test('universal hosts are bare lowercase hosts, not URLs', () {
      for (final target in AppCatalog.all) {
        for (final host in target.universalHosts) {
          expect(host, host.toLowerCase(), reason: host);
          expect(host.contains('/'), isFalse, reason: host);
          expect(host.contains(':'), isFalse, reason: host);
        }
      }
    });

    test('only the documented, source-cited targets claim a verified format',
        () {
      final verified = AppCatalog.all
          .where((t) => t.launchFormatVerified)
          .map((t) => t.key)
          .toSet();
      expect(verified, _verifiedKeys);
    });

    test('coverage: payment and courier filters return their categories', () {
      expect(AppCatalog.paymentApps.map((t) => t.key),
          containsAll(<String>['google_pay', 'phonepe', 'paytm', 'bhim']));
      expect(AppCatalog.courierApps.map((t) => t.key),
          containsAll(<String>['delhivery', 'bluedart', 'fedex', 'dhl']));
      expect(
        AppCatalog.paymentApps.every((t) => t.category == AppCategory.payment),
        isTrue,
      );
      expect(
        AppCatalog.courierApps.every((t) => t.category == AppCategory.courier),
        isTrue,
      );
    });
  });

  group('lookups', () {
    test('byKey round-trips every target and misses cleanly', () {
      for (final target in AppCatalog.all) {
        expect(AppCatalog.byKey(target.key), same(target));
      }
      expect(AppCatalog.byKey('not_an_app'), isNull);
    });

    test('forHost resolves exact hosts', () {
      expect(AppCatalog.forHost('delhivery.com')?.key, 'delhivery');
      expect(AppCatalog.forHost('zoom.us')?.key, 'zoom');
      expect(AppCatalog.forHost('meet.google.com')?.key, 'google_meet');
    });

    test('forHost resolves subdomains via longest-suffix match', () {
      expect(AppCatalog.forHost('sub.delhivery.com')?.key, 'delhivery');
      expect(AppCatalog.forHost('www.delhivery.com')?.key, 'delhivery');
      expect(AppCatalog.forHost('us02web.zoom.us')?.key, 'zoom');
      // teams.microsoft.com is registered exactly and must not be shadowed.
      expect(AppCatalog.forHost('teams.microsoft.com')?.key, 'teams');
      // Case and a trailing FQDN dot are both tolerated.
      expect(AppCatalog.forHost('WWW.Flipkart.com.')?.key, 'flipkart');
    });

    test('forHost returns null for unknown and empty hosts', () {
      expect(AppCatalog.forHost('example.com'), isNull);
      // Suffix match must be label-aligned: notdelhivery.com is not Delhivery.
      expect(AppCatalog.forHost('notdelhivery.com'), isNull);
      expect(AppCatalog.forHost(''), isNull);
      expect(AppCatalog.forHost('   '), isNull);
    });

    test('forUri maps an https tracking link to its app, ignores schemes', () {
      expect(
        AppCatalog.forUri(
                Uri.parse('https://www.delhivery.com/track/package/123'))
            ?.key,
        'delhivery',
      );
      expect(AppCatalog.forUri(Uri.parse('upi://pay?pa=x@ybl')), isNull);
    });
  });

  group('InstalledApps', () {
    test('detect returns exactly the keys whose probe returned true', () async {
      final apps = InstalledApps(
        probe: (uri) async =>
            uri.scheme == 'phonepe' || uri.scheme == 'delhivery',
      );

      expect(await apps.detect(), <String>{'phonepe', 'delhivery'});
      expect(await apps.has('phonepe'), isTrue);
      expect(await apps.has('paytm'), isFalse);
      expect(await apps.has('google_meet'), isFalse,
          reason: 'no probeScheme means never detected');
    });

    test('the result is cached — one sweep across two detect() calls',
        () async {
      var calls = 0;
      final apps = InstalledApps(probe: (uri) async {
        calls++;
        return uri.scheme == 'gpay';
      });

      final first = await apps.detect();
      final probesPerSweep = calls;
      final second = await apps.detect();

      expect(probesPerSweep, AppCatalog.probeSchemes.length);
      expect(calls, probesPerSweep, reason: 'second detect() must not probe');
      expect(second, first);
    });

    test('concurrent first calls share a single sweep', () async {
      var calls = 0;
      final apps = InstalledApps(probe: (uri) async {
        calls++;
        return false;
      });

      await Future.wait(<Future<void>>[
        apps.detect(),
        apps.detect(),
        apps.detect(),
      ]);

      expect(calls, AppCatalog.probeSchemes.length);
    });

    test('refresh re-probes and picks up a newly installed app', () async {
      var installed = false;
      var sweeps = 0;
      final apps = InstalledApps(probe: (uri) async {
        if (uri.scheme == AppCatalog.probeSchemes.first) sweeps++;
        return installed && uri.scheme == 'swiggy';
      });

      expect(await apps.detect(), isEmpty);
      expect(sweeps, 1);

      installed = true;
      await apps.refresh();

      expect(sweeps, 2);
      expect(await apps.detect(), <String>{'swiggy'});
    });

    test('knownHas is null before a sweep and truthful after', () async {
      final apps = InstalledApps(probe: (uri) async => uri.scheme == 'zomato');

      expect(apps.isReady, isFalse);
      expect(apps.knownHas('zomato'), isNull);

      await apps.detect();

      expect(apps.isReady, isTrue);
      expect(apps.knownHas('zomato'), isTrue);
      expect(apps.knownHas('swiggy'), isFalse);
    });

    test('a throwing probe means "not installed", never an exception',
        () async {
      final apps = InstalledApps(probe: (uri) async {
        if (uri.scheme == 'phonepe') return true;
        throw Exception('platform channel exploded for ${uri.scheme}');
      });

      expect(await apps.detect(), <String>{'phonepe'});
      expect(await apps.has('delhivery'), isFalse);
    });

    test('a synchronously throwing probe is also survivable', () async {
      final apps = InstalledApps(probe: (uri) => throw StateError('nope'));

      expect(await apps.detect(), isEmpty);
      expect(apps.knownHas('uber'), isFalse);
    });
  });
}
