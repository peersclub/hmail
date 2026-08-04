import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';
import '../widgets/journey_states.dart';

/// Standalone welcome screen: paints its own liquid-glass backdrop, feature
/// rows in a glass card, fixed CTA block at the bottom.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    // The controller holds phase at signedOut while the OAuth sheet is up
    // (so this screen stays mounted, no shell flash) and reports the in-
    // flight state via [authenticating]. Both count as busy here.
    final syncing = app.authenticating || app.phase == AppPhase.syncing;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: IconBadge(
                        CupertinoIcons.sun_max_fill,
                        tint: Palette.accent(context),
                        size: 76,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Welcome to NoMail',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: Palette.label(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your inbox, minus the inbox.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Palette.secondaryLabel(context),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const GlassSection(
                      children: [
                        GlassRow(
                          icon: CupertinoIcons.doc_text_fill,
                          title: "Bills before they're due",
                          subtitle:
                              'Due dates pulled out of the noise, sorted by urgency.',
                        ),
                        GlassRow(
                          icon: CupertinoIcons.arrow_2_circlepath,
                          title: 'Every subscription, one number',
                          subtitle:
                              'What you actually pay per month, renewals flagged.',
                        ),
                        GlassRow(
                          icon: CupertinoIcons.cube_box_fill,
                          title: 'Packages without tab-hopping',
                          subtitle:
                              'Live delivery status across every merchant.',
                        ),
                        GlassRow(
                          icon: CupertinoIcons.exclamationmark_bubble_fill,
                          title: 'The five emails that matter',
                          subtitle:
                              'Deadlines and alerts surfaced; marketing stays buried.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // While authenticating the phase stays signedOut, so this
                    // progress line remains visible under the OAuth sheet; the
                    // router only swaps to the shell after sign-in succeeds.
                    if (syncing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BusyLine(app.isDemo
                            ? 'Preparing sample data…'
                            : 'Connecting to Google…'),
                      )
                    else if (app.error != null) ...[
                      Text(
                        app.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Palette.destructive(context),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        onPressed: () =>
                            context.read<AppController>().signIn(),
                        child: Text(
                          'Try again',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Palette.label(context),
                          ),
                        ),
                      ),
                    ],
                    AccentButton(
                      'Continue with Google',
                      onPressed: syncing
                          ? null
                          : () => context.read<AppController>().signIn(),
                    ),
                    const SizedBox(height: 10),
                    QuietButton(
                      'Explore with Sample Data',
                      onPressed: syncing
                          ? null
                          : () => context.read<AppController>().enterDemo(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Read-only access. NoMail never sends, moves, or deletes mail.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Palette.secondaryLabel(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
