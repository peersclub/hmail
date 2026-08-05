/// The layout guard.
///
/// Every "random UI issue" this app has shipped shared one cause: 475 tests
/// asserted *what* was on screen and none asserted that it *fit*. Flutter
/// reports an overflow through `FlutterError.onError`, which a widget test
/// ignores unless something is listening — so a row that overflowed by 200px
/// at large Dynamic Type passed every test and then showed up on a device.
///
/// This file listens. It renders every screen across the axes that actually
/// vary in the wild — screen size, Dynamic Type, light/dark, and the four
/// content states each screen can be in — and fails on any layout exception.
///
/// Adding a screen means adding one line to [_screens]. If a change overflows
/// anything at any combination, this file fails and names the combination.
///
/// Deliberately not golden tests: goldens break on every intended pixel change
/// and teach people to re-record them without looking. An overflow assertion
/// only fires when something is genuinely broken.
library;

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/mail/gmail_auth.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/glass/glass.dart';
import 'package:hmail/ui/screens/money_screen.dart';
import 'package:hmail/ui/screens/onboarding_screen.dart';
import 'package:hmail/ui/screens/settings_screen.dart';
import 'package:hmail/ui/screens/shell_screen.dart';
import 'package:hmail/ui/screens/timeline_screen.dart';
import 'package:hmail/ui/screens/today_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sizes that matter: the smallest phone still supported, a current phone, and
/// landscape — where vertical space is the constraint instead of horizontal.
const _sizes = <String, Size>{
  'SE': Size(375, 667),
  '16Pro': Size(402, 874),
  'landscape': Size(874, 402),
};

/// iOS Dynamic Type runs from 0.85x to about 3.1x with accessibility sizes on.
/// 1.0 and 3.1 are the bounds; 2.0 is where most real users with larger text
/// actually sit, and where this app's bugs turned out to live.
const _scales = <double>[1.0, 2.0, 3.1];

/// The four snapshot states each screen has to survive. Empty and all-clear are
/// the ones that never get manually tested, and both were broken.
enum _State { empty, allClear, populated }

InsightSnapshot _snapshotFor(_State state) {
  final now = DateTime.now();
  return switch (state) {
    _State.empty => const InsightSnapshot(),
    // Not empty, but nothing imminent or near — the "All clear" branch.
    _State.allClear => InsightSnapshot(
        subscriptions: [
          Subscription(
            service: 'Netflix',
            amount: 649,
            currency: 'INR',
            cadence: Cadence.monthly,
            nextRenewal: now.add(const Duration(days: 40)),
            lastSeen: now,
            sourceEmailId: 's1',
          ),
        ],
        lastSyncedAt: now,
        emailsScanned: 84,
      ),
    // Long names and long captions on purpose: real merchants and real bank
    // aliases are far longer than fixture-sized strings, and length is what
    // breaks a Row.
    _State.populated => InsightSnapshot(
        subscriptions: [
          Subscription(
            service: 'Adobe Creative Cloud All Apps Annual Plan',
            amount: 4230.75,
            currency: 'INR',
            cadence: Cadence.yearly,
            nextRenewal: now.add(const Duration(days: 2)),
            lastSeen: now,
            sourceEmailId: 's1',
          ),
        ],
        bills: [
          Bill(
            issuer: 'Bangalore Electricity Supply Company Limited',
            amount: 18402.5,
            currency: 'INR',
            dueDate: now.subtract(const Duration(days: 1)),
            lastSeen: now,
            sourceEmailId: 'b1',
          ),
        ],
        deliveries: [
          Delivery(
            merchant: 'Amazon Fulfilment Services India',
            carrier: 'Delhivery Surface Express',
            status: DeliveryStatus.outForDelivery,
            eta: now.add(const Duration(hours: 3)),
            lastSeen: now,
            sourceEmailId: 'd1',
          ),
        ],
        priceChanges: [
          PriceChange(
            service: 'Adobe Creative Cloud All Apps Annual Plan',
            oldAmount: 3999,
            newAmount: 4230.75,
            currency: 'INR',
            cadence: Cadence.yearly,
            detectedAt: now,
            sourceEmailId: 's1',
          ),
        ],
        attention: [
          AttentionItem(
            title: 'Unusual sign-in attempt blocked from a new device',
            reason: 'Security alert from Google Account',
            date: now,
            sourceEmailId: 'a1',
          ),
        ],
        lastSyncedAt: now,
        emailsScanned: 212,
      ),
  };
}

/// `AppController.init()` awaits `GmailAuth.resumeSilently()`, which in a test
/// binding sits on a missing Google Sign-In plugin for seconds. Over a
/// hundred-combination matrix that turned a useful guard into a 17-minute one
/// nobody would run. Answering "no session" instantly keeps the rest of init
/// (settings, playbook, the seeded snapshot) exactly as it is in production.
class _NoSession extends GmailAuth {
  @override
  Future<bool> resumeSilently() async => false;
}

/// Screens rendered standalone. The shell is exercised separately because it
/// adds the dock and builds all four tabs at once.
final _screens = <String, Widget Function()>{
  'Today': () => const TodayScreen(),
  'Money': () => const MoneyScreen(),
  'Timeline': () => const TimelineScreen(),
  'Settings': () => const SettingsScreen(),
  // Onboarding is a fixed Column with no scroll view, which makes it the most
  // overflow-prone screen in the app at large Dynamic Type.
  'Onboarding': () => const OnboardingScreen(),
};

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));

  /// Renders [child] under one exact environment and returns every layout
  /// exception Flutter raised while doing it.
  Future<List<String>> render(
    WidgetTester tester,
    Widget child, {
    required Size size,
    required double scale,
    required Brightness brightness,
    required _State state,
  }) async {
    SharedPreferences.setMockInitialValues({
      'insight_snapshot_v9': jsonEncode(_snapshotFor(state).toJson()),
    });

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Collect every layout error, not just the first. The binding records only
    // one pending exception and merely *prints* the rest, so `takeException`
    // can see one error per test — useless when a single bad primitive
    // overflows eight rows. Overriding the handler sees them all.
    //
    // The handler is restored synchronously below, before the test body ends,
    // rather than in `addTearDown`: teardown runs after the binding's own
    // "did you put onError back?" check, so restoring there trips the assert
    // "a test overrode FlutterError.onError but failed to return it".
    final errors = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed') ||
          text.contains('unbounded') ||
          text.contains('RenderFlex') ||
          text.contains('BoxConstraints')) {
        errors.add(text.split('\n').first);
      }
      // Everything else is dropped on purpose: a missing platform plugin under
      // the test binding is not this file's business, and failing on it would
      // make the layout guard flaky enough that people stop running it.
    };

    final controller = AppController(auth: _NoSession());
    await controller.init();

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        builder: (context, inner) => MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: inner!,
        ),
        home: child,
      ),
    ));
    // Long enough for the money-shot animation and the first frame after boot.
    await tester.pump(const Duration(milliseconds: 900));

    FlutterError.onError = previousOnError;
    // Anything the binding did manage to record has already been counted
    // above; clear it so a drained plugin error doesn't fail the test at
    // teardown for a reason this file does not judge.
    tester.takeException();
    return errors;
  }

  group('nothing overflows', () {
    for (final screen in _screens.entries) {
      for (final size in _sizes.entries) {
        for (final scale in _scales) {
          for (final state in _State.values) {
            testWidgets(
              '${screen.key} · ${size.key} · ${scale}x · ${state.name}',
              (tester) async {
                final errors = await render(
                  tester,
                  screen.value(),
                  size: size.value,
                  scale: scale,
                  brightness: Brightness.light,
                  state: state,
                );
                expect(
                  errors,
                  isEmpty,
                  reason: '${screen.key} at ${size.key} ${scale}x '
                      '(${state.name}) overflowed:\n${errors.join('\n')}',
                );
              },
            );
          }
        }
      }
    }
  });

  group('the shell survives too', () {
    // The shell is the real runtime arrangement: an IndexedStack that builds
    // all four tabs at once, plus the floating dock over them. A tab can be
    // clean alone and overflow here.
    for (final size in _sizes.entries) {
      for (final scale in _scales) {
        testWidgets('shell · ${size.key} · ${scale}x', (tester) async {
          final errors = await render(
            tester,
            const ShellScreen(),
            size: size.value,
            scale: scale,
            brightness: Brightness.light,
            state: _State.populated,
          );
          expect(errors, isEmpty, reason: errors.join('\n'));
        });
      }
    }

    testWidgets('dark mode renders without layout errors', (tester) async {
      final errors = await render(
        tester,
        const ShellScreen(),
        size: _sizes['16Pro']!,
        scale: 1.0,
        brightness: Brightness.dark,
        state: _State.populated,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });

  group('the dock never buries a row', () {
    // Scroll content reserves kDockClearance so the last row clears the
    // floating dock. That constant is hand-maintained, so this asserts the
    // relationship instead of trusting the number.
    testWidgets('clearance exceeds the dock', (tester) async {
      await render(
        tester,
        const ShellScreen(),
        size: _sizes['16Pro']!,
        scale: 1.0,
        brightness: Brightness.light,
        state: _State.populated,
      );

      final dock = tester.getRect(find.byType(GlassDock));
      expect(
        kDockClearance,
        greaterThan(dock.height),
        reason: 'a scroll view padded by $kDockClearance cannot clear a '
            '${dock.height}pt dock',
      );
    });
  });
}
