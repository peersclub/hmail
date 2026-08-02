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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(builder: (_) => const ProcessingScreen()),
      ),
      child: const SizedBox(
        width: 36,
        height: 36,
        child: Center(child: CupertinoActivityIndicator()),
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
