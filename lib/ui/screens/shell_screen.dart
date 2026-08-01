import 'package:flutter/cupertino.dart';

import '../glass/glass.dart';
import 'money_screen.dart';
import 'packages_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// App shell: content behind a floating liquid-glass dock.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: GlassBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(
                index: _index,
                children: [
                  TodayScreen(onNavigate: (tab) => setState(() => _index = tab)),
                  const MoneyScreen(),
                  const PackagesScreen(),
                  const SettingsScreen(),
                ],
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
              child: GlassDock(
                index: _index,
                onChanged: (i) => setState(() => _index = i),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
