/// NoMail liquid-glass design system.
///
/// Every visible surface in the app is built from these primitives. Screens
/// compose them; they never hand-roll containers, colors, or blurs. This is
/// what keeps the app looking like one product instead of four screens.
library;

import 'dart:ui' as ui;

import 'package:cupertino_native_plus/cupertino_native_plus.dart';
import 'package:flutter/cupertino.dart';

import '../../core/palette.dart';

/// Vertical space screens must reserve below scroll content so the floating
/// dock never covers it.
const double kDockClearance = 118;

/// Ambient backdrop: soft vertical wash + two barely-there accent glows.
/// Gives the glass something to refract; never competes with content.
class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Palette.isDark(context);
    final accent = Palette.accent(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0A0C12), Color(0xFF101319)]
              : const [Color(0xFFF3F5FA), Color(0xFFEDEFF4)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            right: -100,
            child: _glow(320, accent.withValues(alpha: dark ? 0.10 : 0.05)),
          ),
          Positioned(
            bottom: -180,
            left: -120,
            child: _glow(380, accent.withValues(alpha: dark ? 0.07 : 0.035)),
          ),
          child,
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

/// The core material: real backdrop blur, gradient glass fill, hairline
/// border, soft ambient shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Palette.isDark(context);
    // Flutter-drawn glass. Native UIGlassEffect platform views composite on
    // a separate layer and desync from Flutter children while scrolling —
    // reserve native glass for static chrome (the dock); scrolling cards
    // must be drawn by Flutter so content clips correctly.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x59000000) : const Color(0x12101828),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0x24FFFFFF), Color(0x0FFFFFFF)]
                    : const [Color(0xD9FFFFFF), Color(0xA8FFFFFF)],
              ),
              border: Border.all(
                width: 1,
                color: dark ? const Color(0x26FFFFFF) : const Color(0xC7FFFFFF),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Large screen title, Airbnb-weight, with optional eyebrow and trailing.
class GlassHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final Widget? trailing;

  const GlassHeader({super.key, required this.title, this.eyebrow, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: TextStyle(
                      fontSize: 15,
                      color: Palette.secondaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    height: 1.05,
                    color: Palette.label(context),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Uppercase section label above a glass card.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 26, 32, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          letterSpacing: -0.1,
          color: Palette.secondaryLabel(context),
        ),
      ),
    );
  }
}

/// Quiet circular icon badge. Neutral by default; pass [tint] only when the
/// row is semantically special (e.g. attention items get the accent).
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final double size;

  const IconBadge(this.icon, {super.key, this.tint, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Palette.secondaryLabel(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint != null
            ? tint!.withValues(alpha: 0.14)
            : Palette.badgeFill(context),
      ),
      child: Icon(icon, size: size * 0.47, color: color),
    );
  }
}

/// Standard row inside a glass card. 60pt, Airbnb-clean.
class GlassRow extends StatelessWidget {
  final IconData icon;
  final Color? iconTint;
  final String title;
  final String? subtitle;
  final String? trailing;
  final String? trailingCaption;
  final Color? trailingCaptionColor;
  final VoidCallback? onTap;
  final int titleMaxLines;
  final int subtitleMaxLines;
  final bool trailingCaptionPill;

  const GlassRow({
    super.key,
    required this.icon,
    this.iconTint,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingCaption,
    this.trailingCaptionColor,
    this.onTap,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
    this.trailingCaptionPill = false,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamic Type: at accessibility text sizes a one-line budget guarantees
    // truncation, so every row earns an extra line once the scaled 17pt body
    // crosses ~22pt (≈ xxxLarge). Rows grow; text never silently disappears.
    final axBoost = MediaQuery.textScalerOf(context).scale(17) >= 22 ? 1 : 0;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          IconBadge(icon, tint: iconTint),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: titleMaxLines + axBoost,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    letterSpacing: -0.4,
                    color: Palette.label(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: subtitleMaxLines + axBoost,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: Palette.secondaryLabel(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null || trailingCaption != null) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (trailing != null)
                  Text(
                    trailing!,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: Palette.label(context),
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                if (trailingCaption != null) ...[
                  const SizedBox(height: 3),
                  if (trailingCaptionPill)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: (trailingCaptionColor ??
                                Palette.secondaryLabel(context))
                            .withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        trailingCaption!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: trailingCaptionColor ??
                              Palette.secondaryLabel(context),
                        ),
                      ),
                    )
                  else
                    Text(
                      trailingCaption!,
                      style: TextStyle(
                        fontSize: 13,
                        color: trailingCaptionColor ??
                            Palette.secondaryLabel(context),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return PressableRow(onTap: onTap!, child: row);
  }
}

/// The tappable wrapper every glass row goes through — and therefore the one
/// place the whole app gets its interaction contract:
///
///  * **Press feedback** (HIG: respond within 100ms): the row dims on touch-
///    down — instantly on press, easing back on release. Opacity only, so
///    nothing shifts or reflows under the finger.
///  * **Screen-reader semantics**: rows announce as buttons and read their
///    texts as one element, instead of a bag of unrelated labels that don't
///    sound tappable.
class PressableRow extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const PressableRow({super.key, required this.onTap, required this.child});

  @override
  State<PressableRow> createState() => _PressableRowState();
}

class _PressableRowState extends State<PressableRow> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          onTap: widget.onTap,
          child: AnimatedOpacity(
            // Down fast (the acknowledgement), up gently (the release).
            opacity: _pressed ? 0.5 : 1,
            duration: Duration(milliseconds: _pressed ? 40 : 180),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Hairline divider between rows inside a glass card (inset past the badge).
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 70),
      child: Container(height: 0.7, color: Palette.hairline(context)),
    );
  }
}

/// A section = label + glass card of rows with dividers.
class GlassSection extends StatelessWidget {
  final String? label;
  final List<Widget> children;

  const GlassSection({super.key, this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) rows.add(const RowDivider());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) SectionLabel(label!),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassCard(child: Column(children: rows)),
        ),
      ],
    );
  }
}

/// Primary filled button (accent) and quiet secondary button.
class AccentButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const AccentButton(this.label, {super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onPressed == null
              ? Palette.accent(context).withValues(alpha: 0.4)
              : Palette.accent(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Palette.accent(context).withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Palette.onAccent(context),
          ),
        ),
      ),
    );
  }
}

class QuietButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const QuietButton(this.label, {super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Palette.label(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small footnote caption, centered.
class Footnote extends StatelessWidget {
  final String text;

  const Footnote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 8, 36, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: Palette.secondaryLabel(context),
        ),
      ),
    );
  }
}

/// Centered empty state.
class GlassEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;

  /// The way forward, rendered as a quiet button under the caption. An empty
  /// state that explains itself but offers no action is a dead end.
  final String? actionLabel;
  final VoidCallback? onAction;

  const GlassEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 44),
      child: Column(
        children: [
          IconBadge(icon, size: 72),
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Palette.label(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Palette.secondaryLabel(context),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            QuietButton(actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// Floating dock backed by Apple's native tab bar — on iOS 26 this renders
/// the system's real Liquid Glass pill, not an approximation.
class GlassDock extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const GlassDock({super.key, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom > 0 ? 0 : 8),
      child: CNTabBar(
        items: const [
          CNTabBarItem(
            label: 'Today',
            icon: CNIcon.symbol('sun.max'),
            activeIcon: CNIcon.symbol('sun.max.fill'),
          ),
          CNTabBarItem(
            label: 'Money',
            icon: CNIcon.symbol('creditcard'),
            activeIcon: CNIcon.symbol('creditcard.fill'),
          ),
          CNTabBarItem(
            label: 'Timeline',
            icon: CNIcon.symbol('square.stack.3d.up'),
            activeIcon: CNIcon.symbol('square.stack.3d.up.fill'),
          ),
          CNTabBarItem(
            label: 'Settings',
            icon: CNIcon.symbol('gearshape'),
            activeIcon: CNIcon.symbol('gearshape.fill'),
          ),
        ],
        currentIndex: index,
        onTap: onChanged,
        tint: Palette.accent(context),
      ),
    );
  }
}
