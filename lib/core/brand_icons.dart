import 'package:flutter/widgets.dart';
import 'package:simple_icons/simple_icons.dart';

/// Resolves a service/brand name or sender domain to a recognizable brand
/// glyph from Simple Icons. Returns null when there's no confident match, so
/// callers fall back to the generic category icon.
///
/// Kept as a lookup (not fuzzy) on purpose: a wrong logo is worse than none.
/// Simple Icons omits some trademarked brands (Amazon, Adobe, Flipkart…); those
/// simply resolve to null and render with the category's default icon.
abstract final class BrandIcons {
  /// Keyed by a lowercase token that appears in the brand name OR the sender
  /// domain. Longest, most specific keys should be checked first (see [forText]).
  static const _byToken = <String, IconData>{
    'netflix': SimpleIcons.netflix,
    'spotify': SimpleIcons.spotify,
    'youtube': SimpleIcons.youtube,
    'substack': SimpleIcons.substack,
    'medium': SimpleIcons.medium,
    'notion': SimpleIcons.notion,
    'audible': SimpleIcons.audible,
    'dropbox': SimpleIcons.dropbox,
    'figma': SimpleIcons.figma,
    'github': SimpleIcons.github,
    'apple': SimpleIcons.apple,
    'icloud': SimpleIcons.apple,
    'google': SimpleIcons.google,
    'gmail': SimpleIcons.gmail,
    'zoom': SimpleIcons.zoom,
    'uber': SimpleIcons.uber,
    'airbnb': SimpleIcons.airbnb,
    'instagram': SimpleIcons.instagram,
    'swiggy': SimpleIcons.swiggy,
    'zomato': SimpleIcons.zomato,
    'paytm': SimpleIcons.paytm,
    'phonepe': SimpleIcons.phonepe,
    'hdfc': SimpleIcons.hdfcbank,
    'icici': SimpleIcons.icicibank,
    'google calendar': SimpleIcons.googlecalendar,
  };

  // Longest keys first so 'google calendar' wins over 'google'.
  static final List<MapEntry<String, IconData>> _ordered = _byToken.entries
      .toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));

  /// Best brand glyph for any of the given strings (service name, source,
  /// sender domain), or null. Case-insensitive substring match.
  static IconData? forText(Iterable<String?> candidates) {
    for (final raw in candidates) {
      if (raw == null || raw.isEmpty) continue;
      final text = raw.toLowerCase();
      for (final entry in _ordered) {
        if (text.contains(entry.key)) return entry.value;
      }
    }
    return null;
  }

  static IconData? forName(String? name) => forText([name]);
}
