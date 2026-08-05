/// Pre-auth story — three full-bleed scenes, auth on the last page.
///
/// Minimal chrome: wordmark, Skip, thin progress, then Next or Google/Sample.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';
import '../onboarding/onboarding_pages.dart';
import '../widgets/journey_states.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  final _pages = onboardingPages();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _skip() async {
    await context.read<AppController>().completeOnboarding();
  }

  void _next() {
    final reduced = MediaQuery.disableAnimationsOf(context);
    _controller.animateToPage(
      _index + 1,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _signIn() async {
    HapticFeedback.lightImpact();
    final app = context.read<AppController>();
    await app.completeOnboarding();
    await app.signIn();
  }

  Future<void> _demo() async {
    HapticFeedback.lightImpact();
    final app = context.read<AppController>();
    await app.completeOnboarding();
    await app.enterDemo();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final last = _index >= _pages.length - 1;
    final syncing = app.authenticating || app.phase == AppPhase.syncing;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final progress = (_index + 1) / _pages.length;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: GlassBackground(
        child: ReadableWidth(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                  child: Row(
                    children: [
                      // Thin progress — not dots.
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 3,
                            child: Stack(
                              children: [
                                ColoredBox(color: Palette.track(context)),
                                FractionallySizedBox(
                                  widthFactor: progress,
                                  child: AnimatedContainer(
                                    duration: reduced
                                        ? Duration.zero
                                        : const Duration(milliseconds: 280),
                                    color: Palette.accent(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        onPressed: syncing ? null : _skip,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Palette.secondaryLabel(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) =>
                        OnboardingPageBody(_pages[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: last
                      ? _AuthBlock(
                          syncing: syncing,
                          error: app.error,
                          isDemo: app.isDemo,
                          onSignIn: _signIn,
                          onDemo: _demo,
                          onRetry: () =>
                              context.read<AppController>().signIn(),
                        )
                      : AccentButton('Continue', onPressed: _next),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBlock extends StatelessWidget {
  final bool syncing;
  final String? error;
  final bool isDemo;
  final VoidCallback onSignIn;
  final VoidCallback onDemo;
  final VoidCallback onRetry;

  const _AuthBlock({
    required this.syncing,
    required this.error,
    required this.isDemo,
    required this.onSignIn,
    required this.onDemo,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (syncing)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BusyLine(
                isDemo ? 'Preparing sample data…' : 'Connecting to Google…'),
          )
        else if (error != null) ...[
          Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Palette.destructive(context),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 6),
            onPressed: onRetry,
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
          onPressed: syncing ? null : onSignIn,
        ),
        const SizedBox(height: 10),
        QuietButton(
          'Explore with Sample Data',
          onPressed: syncing ? null : onDemo,
        ),
        const SizedBox(height: 12),
        Text(
          'Read-only. Never sends, moves, or deletes mail.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Palette.secondaryLabel(context),
          ),
        ),
      ],
    );
  }
}
