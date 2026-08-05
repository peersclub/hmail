/// iPad layout: the app builds as a native iPad app, so the glass system —
/// designed against phone widths — has to stay a readable column instead of
/// stretching to 1366pt.
///
/// These assert the constraint binds on a tablet and is genuinely inert on a
/// phone, because a cap that silently narrowed the iPhone layout would be a
/// worse bug than the stretch it fixes.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/ai/ai_status.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/glass/glass.dart';
import 'package:hmail/ui/screens/scan_screen.dart';
import 'package:hmail/ui/screens/shell_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// iPad Pro 12.9" portrait.
const _iPad = Size(1024, 1366);

/// iPhone 17 Pro.
const _iPhone = Size(402, 874);

/// Kills Dio's transport so the Scanning screen's pricing lookup can't reach
/// the network — an unmocked one leaves a pending timer and fails the test on
/// an invariant rather than on the layout being measured.
class _DeadAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline in tests',
      );

  @override
  void close({bool force = false}) {}
}

AppController _offlineController() => AppController(
      aiStatusService:
          AiStatusService(dio: Dio()..httpClientAdapter = _DeadAdapter()),
    );

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget wrap(AppController controller, Widget child) =>
      ChangeNotifierProvider.value(
        value: controller,
        child: CupertinoApp(home: child),
      );

  group('ReadableWidth', () {
    testWidgets('caps content on a tablet', (tester) async {
      useSize(tester, _iPad);
      await tester.pumpWidget(const CupertinoApp(
        home: ReadableWidth(child: SizedBox.expand()),
      ));

      final box = tester.getSize(find.byType(SizedBox));
      expect(box.width, kReadableWidth);
    });

    testWidgets('is inert on a phone', (tester) async {
      useSize(tester, _iPhone);
      await tester.pumpWidget(const CupertinoApp(
        home: ReadableWidth(child: SizedBox.expand()),
      ));

      // Full phone width, not the cap — the constraint must never narrow the
      // layout it was designed for.
      expect(tester.getSize(find.byType(SizedBox)).width, _iPhone.width);
      expect(_iPhone.width, lessThan(kReadableWidth));
    });
  });

  group('shell', () {
    testWidgets('tab content is capped but the backdrop still fills the iPad',
        (tester) async {
      useSize(tester, _iPad);
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const ShellScreen()));
      await tester.pump(const Duration(milliseconds: 900));

      // ReadableWidth is an Align, so it fills; the cap lands on its child.
      expect(
        tester.getSize(find.byType(IndexedStack)).width,
        kReadableWidth,
      );
      // The wash and its glows are the full screen — only the column narrows.
      expect(
        tester.getSize(find.byType(GlassBackground)).width,
        _iPad.width,
      );
    });

    testWidgets('the dock stays a pill rather than a full-width bar',
        (tester) async {
      useSize(tester, _iPad);
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const ShellScreen()));
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        tester.getSize(find.byType(GlassDock)).width,
        lessThanOrEqualTo(kReadableWidth),
      );
    });
  });

  group('pushed screens', () {
    testWidgets('a settings sub-screen is capped too', (tester) async {
      useSize(tester, _iPad);
      final controller = _offlineController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const ScanScreen()));
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(find.descendant(
              of: find.byType(ReadableWidth),
              matching: find.byType(SafeArea),
            ))
            .width,
        kReadableWidth,
      );
    });
  });

  group('sheets', () {
    testWidgets('a sheet is capped tighter than page content', (tester) async {
      useSize(tester, _iPad);
      expect(kSheetWidth, lessThan(kReadableWidth));

      await tester.pumpWidget(CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showSheet<void>(
              context: context,
              builder: (_) => CupertinoActionSheet(
                title: const Text('Netflix'),
                actions: [
                  CupertinoActionSheetAction(
                    onPressed: () {},
                    child: const Text('Manage plan'),
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Manage plan'), findsOneWidget);
      expect(
        tester.getSize(find.byType(CupertinoActionSheet)).width,
        lessThanOrEqualTo(kSheetWidth),
      );
    });
  });
}
