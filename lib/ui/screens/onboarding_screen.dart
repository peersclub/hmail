/// First run: three scenes, then sign in.
///
/// ## Why this was rebuilt rather than tuned
///
/// The previous carousel called `setState` from a scroll listener, so during a
/// swipe the whole subtree rebuilt 60–120 times a second: the backdrop and its
/// two radial gradients, every live page, and every page body. On top of that,
/// each page was wrapped in `Opacity` — which forces a `saveLayer` — over
/// content containing frosted fills. A `saveLayer` around blurred content is
/// the most expensive thing you can put on a moving layer, because the GPU
/// re-composites an offscreen buffer per page per frame.
///
/// No curve tuning fixes that. Smoothness had to be structural:
///
///  1. **Nothing rebuilds on scroll.** The swipe is read through
///     `AnimatedBuilder(animation: _pages)` — a `PageController` is a
///     `Listenable` — and every such builder is handed its subtree via the
///     `child:` parameter, which Flutter passes through untouched. So a drag
///     re-runs a handful of `Transform`s and repaints two `CustomPaint`s, and
///     rebuilds no page content at all.
///  2. **`RepaintBoundary` per page**, so painting the page you are dragging in
///     never repaints the one you are dragging out.
///  3. **Scene bodies rebuild once per settle**, driven by `_settled` — not by
///     the continuous offset.
///  4. **`FadeTransition`/`SlideTransition` over `Opacity`/`Transform`** inside
///     scenes: they animate the layer instead of rebuilding the widget.
///  5. **No `BackdropFilter` in a moving subtree.** See `onboarding_scenes.dart`.
///
/// ## Haptics
///
/// Three moments, deliberately few — a haptic on everything means nothing.
/// `selectionClick` on page settle (the lightest tick iOS has, matching a
/// picker), `mediumImpact` once when scene one resolves noise into insights
/// (the app's thesis landing), and `lightImpact` on the buttons that commit.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';
import '../onboarding/onboarding_scenes.dart';
import '../widgets/journey_states.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();

  /// The settled page. Changes once per swipe, and is the *only* thing that
  /// rebuilds scene content.
  int _settled = 0;

  static const _sceneCount = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Continuous offset, read on demand instead of stored in state.
  ///
  /// Before the first layout there are no dimensions to ask about, so this
  /// falls back to the settled page rather than throwing or reporting zero.
  double get _offset {
    if (!_pages.hasClients || !_pages.position.haveDimensions) {
      return _settled.toDouble();
    }
    return _pages.page ?? _settled.toDouble();
  }

  void _onSettled(int index) {
    if (index == _settled) return;
    HapticFeedback.selectionClick();
    setState(() => _settled = index);
  }

  void _next() {
    HapticFeedback.lightImpact();
    _pages.animateToPage(
      (_settled + 1).clamp(0, _sceneCount - 1),
      // 520ms with a decelerating curve: long enough for the parallax to read
      // as depth, short enough that a second tap never feels blocked.
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _skip() async {
    await context.read<AppController>().completeOnboarding();
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
    final busy = app.authenticating || app.phase == AppPhase.syncing;
    final onLast = _settled == _sceneCount - 1;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: GlassBackground(
        child: ReadableWidth(
          child: SafeArea(
            child: Column(
              children: [
                _Chrome(
                  pages: _pages,
                  settled: _settled,
                  count: _sceneCount,
                  onSkip: busy ? null : _skip,
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _sceneCount,
                    onPageChanged: _onSettled,
                    // iOS-native feel: page snapping with rubber-band
                    // overscroll at the ends.
                    physics: const PageScrollPhysics()
                        .applyTo(const BouncingScrollPhysics()),
                    itemBuilder: (context, index) => RepaintBoundary(
                      child: _Scene(
                        index: index,
                        pages: _pages,
                        offsetOf: () => _offset,
                        active: _settled == index,
                      ),
                    ),
                  ),
                ),
                _Footer(
                  onLast: onLast,
                  busy: busy,
                  error: app.error,
                  isDemo: app.isDemo,
                  onContinue: _next,
                  onSignIn: _signIn,
                  onDemo: _demo,
                  onRetry: () => context.read<AppController>().signIn(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Progress rail and Skip.
///
/// The rail tracks the *continuous* offset, so it grows under the thumb during
/// a drag instead of jumping when the page snaps — the single cheapest thing
/// that makes a carousel feel connected to the finger.
class _Chrome extends StatelessWidget {
  final PageController pages;
  final int settled;
  final int count;
  final VoidCallback? onSkip;

  const _Chrome({
    required this.pages,
    required this.settled,
    required this.count,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: pages,
              builder: (context, _) {
                final page = (pages.hasClients &&
                        pages.position.haveDimensions)
                    ? (pages.page ?? settled.toDouble())
                    : settled.toDouble();
                return _Rail(progress: ((page + 1) / count).clamp(0.0, 1.0));
              },
            ),
          ),
          const SizedBox(width: 12),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            onPressed: onSkip,
            child: Text(
              'Skip',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: Palette.secondaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final double progress;

  const _Rail({required this.progress});

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
            // FractionallySizedBox rather than an animated width: no layout
            // pass, and it follows the drag exactly.
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

/// One page: an ambient backdrop that drifts, and the scene itself, both
/// parallaxed off the swipe offset.
///
/// The scene widget is created once per settle and handed to `AnimatedBuilder`
/// as `child`, so the drag moves it without rebuilding it.
class _Scene extends StatelessWidget {
  final int index;
  final PageController pages;
  final double Function() offsetOf;
  final bool active;

  const _Scene({
    required this.index,
    required this.pages,
    required this.offsetOf,
    required this.active,
  });

  Widget _body() => switch (index) {
        0 => InboxScene(active: active),
        1 => PriceScene(active: active),
        _ => DestinationScene(active: active),
      };

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: _body(),
    );

    if (reduced) return content;

    return AnimatedBuilder(
      animation: pages,
      child: content,
      builder: (context, child) {
        final delta = offsetOf() - index;
        final away = delta.abs().clamp(0.0, 1.0);
        // Ease the falloff so a page leaving dissolves rather than snapping to
        // transparent halfway through the gesture.
        final falloff = Curves.easeOut.transform(away);

        return Stack(
          children: [
            // Backdrop drifts at a third of the content's rate: the difference
            // between the two speeds is what the eye reads as depth.
            Positioned.fill(
              child: IgnorePointer(
                child: SceneBackdrop(phase: delta * 0.34, seed: 7 + index * 31),
              ),
            ),
            Positioned.fill(
              child: Opacity(
                // Exactly 1.0 at rest, so Flutter skips the saveLayer entirely
                // and a still page costs nothing to composite.
                opacity: 1.0 - falloff * 0.6,
                child: Transform.translate(
                  offset: Offset(delta * -34, falloff * 10),
                  child: Transform.scale(
                    scale: 1.0 - falloff * 0.05,
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Continue on the first two scenes; the auth block on the last.
///
/// Cross-fades with a slight lift so the change of purpose is felt rather than
/// noticed — a hard swap here reads as a bug.
class _Footer extends StatelessWidget {
  final bool onLast;
  final bool busy;
  final String? error;
  final bool isDemo;
  final VoidCallback onContinue;
  final VoidCallback onSignIn;
  final VoidCallback onDemo;
  final VoidCallback onRetry;

  const _Footer({
    required this.onLast,
    required this.busy,
    required this.error,
    required this.isDemo,
    required this.onContinue,
    required this.onSignIn,
    required this.onDemo,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 6, 26, 14),
      child: AnimatedSize(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.14),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: onLast
              ? _Auth(
                  key: const ValueKey('auth'),
                  busy: busy,
                  error: error,
                  isDemo: isDemo,
                  onSignIn: onSignIn,
                  onDemo: onDemo,
                  onRetry: onRetry,
                )
              : _PressableButton(
                  key: const ValueKey('continue'),
                  label: 'Continue',
                  onPressed: onContinue,
                ),
        ),
      ),
    );
  }
}

/// An [AccentButton] that dips 2.5% under the thumb.
///
/// `AnimatedScale` rather than a controller: the press is a one-shot 110ms
/// change, and HIG asks for feedback inside 100ms — a tween that starts on the
/// same frame as the touch is the cheapest way to hit that.
class _PressableButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _PressableButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
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
        duration: reduced ? Duration.zero : const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AccentButton(widget.label, onPressed: widget.onPressed),
      ),
    );
  }
}

class _Auth extends StatelessWidget {
  final bool busy;
  final String? error;
  final bool isDemo;
  final VoidCallback onSignIn;
  final VoidCallback onDemo;
  final VoidCallback onRetry;

  const _Auth({
    super.key,
    required this.busy,
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
        if (busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BusyLine(
              isDemo ? 'Preparing sample data…' : 'Connecting to Google…',
            ),
          )
        else if (error != null) ...[
          Text(
            error!,
            textAlign: TextAlign.center,
            maxLines: 3,
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
        _PressableButton(
          label: 'Continue with Google',
          onPressed: busy ? () {} : onSignIn,
        ),
        const SizedBox(height: 10),
        QuietButton(
          'Explore with Sample Data',
          onPressed: busy ? null : onDemo,
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
