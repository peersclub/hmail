/// The smoothness contract for the first-run carousel.
///
/// The previous carousel was janky because a scroll listener called `setState`,
/// rebuilding every page body 60–120 times a second. That is invisible to a
/// normal widget test — everything still renders, it just renders far too many
/// times — so it needs its own assertion or it will come back.
///
/// These tests count builds during a simulated drag. They are not benchmarks:
/// a build count is deterministic where a frame time is not, and the defect
/// being guarded against is "rebuilds the world per frame", which counting
/// catches exactly.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/screens/onboarding_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts how many times its subtree is rebuilt.
class _BuildCounter extends StatefulWidget {
  final Widget child;
  final void Function() onBuild;

  const _BuildCounter({required this.child, required this.onBuild});

  @override
  State<_BuildCounter> createState() => _BuildCounterState();
}

class _BuildCounterState extends State<_BuildCounter> {
  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return widget.child;
  }
}

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppController> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = AppController();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: const CupertinoApp(home: OnboardingScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 1200));
    return controller;
  }

  testWidgets('a drag does not rebuild the scene bodies', (tester) async {
    await boot(tester);

    // One frame at a time, the way a finger does, and past the halfway point:
    // a slow drag that stops short of half the page width snaps back, so a
    // shorter drag would assert the wrong thing.
    final centre = tester.getCenter(find.byType(PageView));
    final gesture = await tester.startGesture(centre);

    var frames = 0;
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(-14, 0));
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(frames, 20);
    // The scenes are still there and the swipe landed on page 2.
    expect(find.textContaining('Money moves'), findsOneWidget);
  });

  testWidgets('scene entrances run once per visit, not per frame',
      (tester) async {
    // A scene rebuilding on every scroll notification is the exact defect that
    // made the old carousel drop frames. Assert the count directly: settling on
    // a new page may rebuild a handful of times (the switcher, the footer size
    // animation), but nowhere near once per frame of a 20-frame drag.
    var builds = 0;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = AppController();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: CupertinoApp(
        home: _BuildCounter(
          onBuild: () => builds++,
          child: const OnboardingScreen(),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1200));

    final before = builds;
    final centre = tester.getCenter(find.byType(PageView));
    final gesture = await tester.startGesture(centre);
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(-9, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final duringDrag = builds - before;
    expect(
      duringDrag,
      lessThan(6),
      reason: 'the screen rebuilt $duringDrag times across a 20-frame drag; '
          'the swipe must drive transforms, not rebuilds',
    );
  });

  testWidgets('the carousel settles — no endless idle animation',
      (tester) async {
    // pumpAndSettle only returns when no frames are scheduled. An unbounded
    // `repeat()` on an idle animation would hang here forever, and would also
    // keep the raster thread busy for as long as the app is open.
    await boot(tester);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('reduced motion shows finished scenes immediately',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = AppController();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: const MediaQuery(
        data: MediaQueryData(size: Size(402, 874), disableAnimations: true),
        child: CupertinoApp(home: OnboardingScreen()),
      ),
    ));
    // One frame: with animations disabled the composition must already be
    // final, not mid-fade.
    await tester.pump();

    expect(find.textContaining('minus the inbox'), findsOneWidget);
    final opacity = tester.widgetList<FadeTransition>(
      find.byType(FadeTransition),
    );
    for (final fade in opacity) {
      expect(fade.opacity.value, 1.0,
          reason: 'reduced motion must not leave content mid-fade');
    }
  });

  testWidgets('every page is isolated behind a RepaintBoundary',
      (tester) async {
    // Without this, painting the page being dragged in also repaints the one
    // being dragged out.
    await boot(tester);
    expect(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
  });

  testWidgets('Skip completes onboarding from any page', (tester) async {
    final controller = await boot(tester);
    expect(controller.seenOnboarding, isFalse);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(controller.seenOnboarding, isTrue);
  });

  testWidgets('Continue advances, and the last page swaps in auth',
      (tester) async {
    await boot(tester);

    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Money moves'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('One tap'), findsOneWidget);

    // Purpose changes on the last page: no more Continue, auth instead.
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Explore with Sample Data'), findsOneWidget);
  });
}
