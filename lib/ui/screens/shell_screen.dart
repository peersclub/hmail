import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../state/app_controller.dart';
import '../glass/glass.dart';
import 'money_screen.dart';
import 'settings_screen.dart';
import 'timeline_screen.dart';
import 'today_screen.dart';

/// App shell: content behind a floating liquid-glass dock.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;
  AppController? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Notification taps land on a destination, not just the foreground:
    // the controller posts a tab request, the shell consumes it.
    final app = context.read<AppController>();
    if (!identical(app, _app)) {
      _app?.tabRequest.removeListener(_onTabRequest);
      _app = app;
      app.tabRequest.addListener(_onTabRequest);
      _onTabRequest(); // consume one that fired before the shell mounted
    }
  }

  void _onTabRequest() {
    final tab = _app?.tabRequest.value;
    if (tab == null) return;
    _app?.tabRequest.value = null;
    if (mounted && tab >= 0 && tab <= 3) setState(() => _index = tab);
  }

  @override
  void dispose() {
    _app?.tabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: GlassBackground(
        child: Stack(
          children: [
            // One constraint for all four tabs: the backdrop and its glows
            // still fill the screen, only the content column is capped.
            Positioned.fill(
              child: ReadableWidth(
                child: IndexedStack(
                  index: _index,
                  children: [
                    TodayScreen(
                        onNavigate: (tab) => setState(() => _index = tab)),
                    const MoneyScreen(),
                    const TimelineScreen(),
                    const SettingsScreen(),
                  ],
                ),
              ),
            ),
            // Status-bar scrim: keeps scrolled content legible under the clock.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Builder(builder: (context) {
                  final dark = MediaQuery.platformBrightnessOf(context) ==
                      Brightness.dark;
                  final top = dark
                      ? const Color(0xFF0A0C12)
                      : const Color(0xFFF3F5FA);
                  return Container(
                    height: MediaQuery.paddingOf(context).top + 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.55, 1],
                        colors: [top, top, top.withValues(alpha: 0)],
                      ),
                    ),
                  );
                }),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                // The dock is a floating pill, not a full-width tab bar — on
                // an iPad it has to stay a pill.
                constraints: const BoxConstraints(maxWidth: kReadableWidth),
                child: GlassDock(
                  index: _index,
                  onChanged: (i) => setState(() => _index = i),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
