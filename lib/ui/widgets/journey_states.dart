/// Shared journey-state widgets: small, in-flow pieces screens compose when
/// they have nothing (or nothing yet) to show. In-flow by design — status
/// lives inside the layout, never as an overlay that could cover controls.
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';
import '../screens/processing_screen.dart';

/// Inline progress line: spinner plus what is happening right now.
/// Centered, one line, 15pt secondary — quiet enough to sit near buttons.
class BusyLine extends StatelessWidget {
  final String text;

  const BusyLine(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CupertinoActivityIndicator(radius: 9),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: Palette.secondaryLabel(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Header badge while a sync runs: the spinner is where people look when they
/// wonder whether the app has hung, so it answers — tap it for the live
/// pipeline. Sized to match the 36pt account bubble it replaces.
class SyncBusyBadge extends StatelessWidget {
  const SyncBusyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scanning your inbox. Opens the live pipeline',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(builder: (_) => const ProcessingScreen()),
        ),
        // 44pt hit target (HIG minimum); the indicator stays visually small.
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ),
    );
  }
}

/// Placeholder rows while the first scan runs — the shape of what's coming,
/// not a spinner. A minutes-long scan behind a lone spinner reads as "hung";
/// skeleton rows read as "filling up" (HIG progressive loading).
///
/// Pulses gently; goes static when the user asked the system for reduced
/// motion. Hidden from screen readers — the live progress text nearby is the
/// accessible signal.
class SkeletonRows extends StatefulWidget {
  final int count;

  const SkeletonRows({super.key, this.count = 3});

  @override
  State<SkeletonRows> createState() => _SkeletonRowsState();
}

class _SkeletonRowsState extends State<SkeletonRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
    upperBound: 0.9,
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _pulse.stop();
      _pulse.value = 0.7;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }

    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Palette.badgeFill(context),
            borderRadius: BorderRadius.circular(height / 2),
          ),
        );

    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: FadeTransition(
          opacity: _pulse,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < widget.count; i++)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Palette.badgeFill(context),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Vary widths so it reads as content, not bars.
                              bar(120.0 + (i * 37) % 80, 12),
                              const SizedBox(height: 7),
                              bar(80.0 + (i * 53) % 110, 9),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The action that fills an empty screen: run the Gmail scan. A quiet glass
/// button so empty states can offer recovery without shouting. Disables
/// itself (and says so) while a sync is already running.
class ScanActionButton extends StatelessWidget {
  final String label;

  const ScanActionButton({super.key, this.label = 'Scan My Gmail'});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final syncing = app.phase == AppPhase.syncing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(60, 0, 60, 8),
      child: QuietButton(
        syncing ? 'Scanning…' : label,
        onPressed:
            syncing ? null : () => context.read<AppController>().sync(),
      ),
    );
  }
}
