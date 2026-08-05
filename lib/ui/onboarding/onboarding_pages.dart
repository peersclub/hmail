/// Full-bleed onboarding scenes — editorial, not UI screenshots.
///
/// No device frames. No feature lists. One composition per page:
/// brand → extraction → invite. Motion is the story.
library;

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../../core/palette.dart';
import '../glass/glass.dart';

class OnboardingPageData {
  final Widget Function(BuildContext context) scene;

  const OnboardingPageData({required this.scene});
}

List<OnboardingPageData> onboardingPages() => [
      OnboardingPageData(scene: (_) => const _BrandScene()),
      OnboardingPageData(scene: (_) => const _ExtractScene()),
      OnboardingPageData(scene: (_) => const _InviteScene()),
    ];

class OnboardingPageBody extends StatelessWidget {
  final OnboardingPageData data;

  const OnboardingPageBody(this.data, {super.key});

  @override
  Widget build(BuildContext context) => data.scene(context);
}

// ── Scene 1: brand ───────────────────────────────────────────────────────

class _BrandScene extends StatefulWidget {
  const _BrandScene();

  @override
  State<_BrandScene> createState() => _BrandSceneState();
}

class _BrandSceneState extends State<_BrandScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = Palette.label(context);
    final secondary = Palette.secondaryLabel(context);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_c.value);
        final late = Curves.easeOut.transform(
          ((_c.value - 0.35) / 0.65).clamp(0.0, 1.0),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 3),
              Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 28 * (1 - t)),
                  child: Text(
                    'NoMail',
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2.4,
                      height: 0.95,
                      color: label,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Opacity(
                opacity: late,
                child: Transform.translate(
                  offset: Offset(0, 16 * (1 - late)),
                  child: Text(
                    'Your inbox,\nminus the inbox.',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.6,
                      height: 1.2,
                      color: secondary,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 4),
              Opacity(
                opacity: late,
                child: Text(
                  'Email is where life leaves receipts.\nWe keep the ones that matter.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: secondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

// ── Scene 2: extraction ──────────────────────────────────────────────────

class _ExtractScene extends StatefulWidget {
  const _ExtractScene();

  @override
  State<_ExtractScene> createState() => _ExtractSceneState();
}

class _ExtractSceneState extends State<_ExtractScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Palette.secondaryLabel(context);
    final label = Palette.label(context);

    final chips = [
      (0.18, -0.55, -0.15, 'BESCOM', 'Due tomorrow', '₹1,840'),
      (0.32, 0.35, -0.42, 'Netflix', 'Renews Friday', '₹649'),
      (0.46, -0.25, 0.38, 'Delhivery', 'Out for delivery', 'Track'),
      (0.60, 0.55, 0.22, 'Product sync', 'Today · 8pm', 'Join'),
    ];

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final mailFade = (1 - Curves.easeIn.transform((t / 0.45).clamp(0.0, 1.0)))
            .clamp(0.0, 1.0);
        final copyIn = Curves.easeOut.transform(
          ((t - 0.55) / 0.45).clamp(0.0, 1.0),
        );

        return Stack(
          children: [
            // Ghost mail — the noise that dissolves.
            Positioned.fill(
              child: Opacity(
                opacity: mailFade * 0.55,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in const [
                        'HDFC Bank — Statement ready',
                        'Netflix — Your plan renews soon',
                        '50% OFF this weekend only!!!!',
                        'Delhivery — Shipped via Bluedart',
                        'BESCOM — Bill generated for Jul',
                        'Swiggy — ₹200 off on orders above',
                        'LinkedIn — People are viewing',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.1,
                              color: secondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Extracted chips float into place.
            for (var i = 0; i < chips.length; i++)
              _FloatingChip(
                progress: t,
                startAt: chips[i].$1,
                xAlign: chips[i].$2,
                yAlign: chips[i].$3,
                title: chips[i].$4,
                subtitle: chips[i].$5,
                trailing: chips[i].$6,
              ),
            // Copy at the bottom of the composition.
            Positioned(
              left: 28,
              right: 28,
              bottom: 8,
              child: Opacity(
                opacity: copyIn,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - copyIn)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pulled from the noise.',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          height: 1.15,
                          color: label,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bills, renewals, packages, meetings —\nranked by what needs you.',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: secondary,
                        ),
                      ),
                    ],
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

class _FloatingChip extends StatelessWidget {
  final double progress;
  final double startAt;
  final double xAlign;
  final double yAlign;
  final String title;
  final String subtitle;
  final String trailing;

  const _FloatingChip({
    required this.progress,
    required this.startAt,
    required this.xAlign,
    required this.yAlign,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final local = ((progress - startAt) / (1 - startAt)).clamp(0.0, 1.0);
    final t = Curves.easeOutCubic.transform(local);
    // Drift in from slightly below + scale up.
    final dy = 36 * (1 - t);
    final scale = 0.92 + 0.08 * t;

    return Align(
      alignment: Alignment(xAlign, yAlign),
      child: Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            child: _GlassChip(
              title: title,
              subtitle: subtitle,
              trailing: trailing,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;

  const _GlassChip({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Palette.isDark(context)
                ? const Color(0x33FFFFFF)
                : const Color(0xCCFFFFFF),
            border: Border.all(
              color: Palette.isDark(context)
                  ? const Color(0x28FFFFFF)
                  : const Color(0x66FFFFFF),
            ),
            boxShadow: [
              BoxShadow(
                color: Palette.isDark(context)
                    ? const Color(0x66000000)
                    : const Color(0x14000000),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: Palette.label(context),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Palette.secondaryLabel(context),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                trailing,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                  color: Palette.label(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Scene 3: invite ──────────────────────────────────────────────────────

class _InviteScene extends StatefulWidget {
  const _InviteScene();

  @override
  State<_InviteScene> createState() => _InviteSceneState();
}

class _InviteSceneState extends State<_InviteScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = Palette.label(context);
    final secondary = Palette.secondaryLabel(context);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_c.value);
        final late = Curves.easeOut.transform(
          ((_c.value - 0.3) / 0.7).clamp(0.0, 1.0),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - t)),
                  child: Text(
                    'One tap\nresolves it.',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.8,
                      height: 1.0,
                      color: label,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Opacity(
                opacity: late,
                child: Transform.translate(
                  offset: Offset(0, 14 * (1 - late)),
                  child: const _ActionPreview(),
                ),
              ),
              const Spacer(flex: 3),
              Opacity(
                opacity: late,
                child: Text(
                  'Pay the bill. Track the package.\nJoin the meeting. Without digging.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: secondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _ActionPreview extends StatelessWidget {
  const _ActionPreview();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Palette.accent(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Palette.accent(context).withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Text(
            'Pay via UPI  ·  ₹1,840',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Palette.onAccent(context),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _QuietPill('Track package')),
            const SizedBox(width: 8),
            Expanded(child: _QuietPill('Join Meet')),
          ],
        ),
      ],
    );
  }
}

class _QuietPill extends StatelessWidget {
  final String label;

  const _QuietPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Palette.badgeFill(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Palette.label(context),
        ),
      ),
    );
  }
}
