/// Pre-auth story — three full-bleed scenes, auth on the last page.
///
/// Swipe uses a soft parallax fade (not a hard clip). Progress and the footer
/// track the continuous page offset so nothing jumps on settle.
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
  late final PageController _controller;
  final _pages = onboardingPages();

  /// Continuous page position (0.0 … n-1). Drives progress, parallax, footer.
  double _page = 0;
  int _settled = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients || !_controller.position.haveDimensions) {
      return;
    }
    final next = _controller.page ?? _page;
    if ((next - _page).abs() < 0.001) return;
    setState(() => _page = next);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _skip() async {
    await context.read<AppController>().completeOnboarding();
  }

  void _next() {
    final reduced = MediaQuery.disableAnimationsOf(context);
    _controller.animateToPage(
      _settled + 1,
      duration:
          reduced ? Duration.zero : const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
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

  void _onPageSettled(int i) {
    if (i == _settled) return;
    HapticFeedback.selectionClick();
    setState(() {
      _settled = i;
      _page = i.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final syncing = app.authenticating || app.phase == AppPhase.syncing;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final last = _page >= _pages.length - 1.08;
    // Progress fills smoothly as you drag, not only on snap.
    final progress = ((_page + 1) / _pages.length).clamp(0.0, 1.0);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: GlassBackground(
        child: ReadableWidth(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ProgressRail(
                          progress: progress,
                          reduced: reduced,
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
                    // Soft overscroll + page snap — less "clunk" than default.
                    physics: const BouncingScrollPhysics(
                      parent: PageScrollPhysics(),
                    ),
                    onPageChanged: _onPageSettled,
                    itemBuilder: (context, i) {
                      return _ParallaxPage(
                        index: i,
                        page: _page,
                        reduced: reduced,
                        child: OnboardingPageBody(
                          _pages[i],
                          active: (i - _page).abs() < 0.45,
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: AnimatedSwitcher(
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(anim);
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: last
                        ? KeyedSubtree(
                            key: const ValueKey('auth'),
                            child: _AuthBlock(
                              syncing: syncing,
                              error: app.error,
                              isDemo: app.isDemo,
                              onSignIn: _signIn,
                              onDemo: _demo,
                              onRetry: () =>
                                  context.read<AppController>().signIn(),
                            ),
                          )
                        : KeyedSubtree(
                            key: const ValueKey('continue'),
                            child: _ContinueButton(onPressed: _next),
                          ),
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

/// Continuous ink rail — width tracks drag, not just settled page.
class _ProgressRail extends StatelessWidget {
  final double progress;
  final bool reduced;

  const _ProgressRail({required this.progress, required this.reduced});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Palette.track(context)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: ColoredBox(color: Palette.accent(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft fade + scale + lateral drift while the page is mid-swipe.
class _ParallaxPage extends StatelessWidget {
  final int index;
  final double page;
  final bool reduced;
  final Widget child;

  const _ParallaxPage({
    required this.index,
    required this.page,
    required this.reduced,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (reduced) return child;

    final delta = page - index;
    final abs = delta.abs().clamp(0.0, 1.0);
    // Ease the falloff so the leaving page dissolves instead of clipping.
    final falloff = Curves.easeOut.transform(abs);
    final opacity = (1.0 - falloff * 0.55).clamp(0.0, 1.0);
    final scale = (1.0 - falloff * 0.045).clamp(0.94, 1.0);
    final dx = delta * -28;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(dx, 8 * falloff),
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

class _ContinueButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _ContinueButton({required this.onPressed});

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.975 : 1,
        duration: reduced
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AccentButton('Continue', onPressed: widget.onPressed),
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
