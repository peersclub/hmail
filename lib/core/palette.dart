import 'package:flutter/cupertino.dart';

/// NoMail color discipline — neutral-first, one accent.
///
/// Rules the whole UI follows:
///  * ONE accent: monochrome ink. Used for: primary buttons, active dock
///    item, the attention badge, data-viz shades.
///  * Red/orange exist ONLY as urgency text (never fills, never icons).
///  * Everything else is label/secondary/tertiary neutrals on glass.
abstract final class Palette {
  static bool isDark(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;

  /// Ink accent — near-black in light, near-white in dark. Premium
  /// monochrome (Uber-style); never a decorative hue.
  static Color accent(BuildContext context) => isDark(context)
      ? const Color(0xFFF2F3F5)
      : const Color(0xFF15171B);

  /// Foreground on top of an accent fill.
  static Color onAccent(BuildContext context) => isDark(context)
      ? const Color(0xFF101214)
      : const Color(0xFFFFFFFF);

  static Color label(BuildContext context) =>
      CupertinoColors.label.resolveFrom(context);
  static Color secondaryLabel(BuildContext context) =>
      CupertinoColors.secondaryLabel.resolveFrom(context);
  static Color tertiaryLabel(BuildContext context) =>
      CupertinoColors.tertiaryLabel.resolveFrom(context);

  /// Quiet circular badge fill behind row icons.
  static Color badgeFill(BuildContext context) => isDark(context)
      ? const Color(0x1FFFFFFF)
      : const Color(0x0F000000);

  /// Hairline dividers inside glass cards.
  static Color hairline(BuildContext context) => isDark(context)
      ? const Color(0x1AFFFFFF)
      : const Color(0x14000000);

  /// Neutral track for progress/share bars.
  static Color track(BuildContext context) => isDark(context)
      ? const Color(0x24FFFFFF)
      : const Color(0x11000000);

  static Color destructive(BuildContext context) =>
      CupertinoColors.systemRed.resolveFrom(context);

  /// Urgency is text-only. Red when overdue, orange within 3 days,
  /// secondary otherwise.
  static Color urgency(BuildContext context, DateTime? date,
      {bool overdue = false}) {
    if (overdue) return CupertinoColors.systemRed.resolveFrom(context);
    if (date == null) return secondaryLabel(context);
    final days = DateTime(date.year, date.month, date.day)
        .difference(DateTime.now())
        .inDays;
    if (days < 0) return CupertinoColors.systemRed.resolveFrom(context);
    if (days <= 3) return CupertinoColors.systemOrange.resolveFrom(context);
    return secondaryLabel(context);
  }

  /// Top and bottom stops of the app's ambient backdrop wash.
  ///
  /// Lives here rather than inside `GlassBackground` because the status-bar
  /// scrim has to fade from the *same* top colour. Two copies of a colour are
  /// two colours as soon as one of them changes.
  static Color backdropTop(BuildContext context) => isDark(context)
      ? const Color(0xFF0A0C12)
      : const Color(0xFFF3F5FA);

  static Color backdropBottom(BuildContext context) => isDark(context)
      ? const Color(0xFF101319)
      : const Color(0xFFEDEFF4);

  /// Monochrome ink ramp for data viz.
  static List<Color> ramp(BuildContext context) {
    final base = accent(context);
    return [
      base.withValues(alpha: 0.92),
      base.withValues(alpha: 0.64),
      base.withValues(alpha: 0.42),
      base.withValues(alpha: 0.24),
    ];
  }
}
