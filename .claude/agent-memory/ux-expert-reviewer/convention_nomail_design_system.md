---
name: convention-nomail-design-system
description: NoMail's design-system conventions relevant to UX review (monochrome ink, glass sections, recurring gotchas)
metadata:
  type: reference
---

Source of truth: `lib/core/palette.dart` (color discipline) and
`lib/ui/glass/glass.dart` (component library). Read both before reviewing any
NoMail screen.

Rules:
- ONE accent color: monochrome ink (near-black light / near-white dark). Red
  (`CupertinoColors.systemRed`) and orange (`systemOrange`) exist ONLY as
  urgency *text*, never fills/icons/badges. Any review recommendation that
  introduces a second hue is off-system — reach for opacity/weight variation
  on the ink accent instead.
- `GlassSection` (glass.dart ~L371): labeled sections get `SectionLabel`
  padding of `fromLTRB(32, 26, 32, 10)` before the card — i.e. ~36px of
  separation baked in. Unlabeled sections (label: null) get nothing from
  `GlassSection` itself — all spacing above an unlabeled section has to come
  from the caller. This is a recurring gap: callers that reuse
  `_DomainSection`/`GlassSection` without a label tend to under-pad, because
  the labeled case "looks fine" by accident and the unlabeled case is never
  checked against it. Always compare labeled vs. unlabeled top-spacing
  side-by-side when reviewing a screen that toggles between them.
- Existing separator convention for "label + secondary detail" is a middot
  (" · "), used in `insight_mapper.dart` for subtitle composition
  (`'${f.source} · ${formatDay(f.date)}'`) and in glass.dart's trailing
  caption. New label+value pairings (e.g. chip label + count) should match
  this rather than inventing a bare-space juxtaposition.
- `Palette.secondaryLabel`/`badgeFill` are themselves already reduced-contrast
  neutrals. Stacking an additional `.withValues(alpha: ...)` on top of
  `secondaryLabel` (as seen in the filter-chip count) compounds two contrast
  reductions — worth an explicit contrast check any time this pattern
  reappears, not just an eyeball pass.
- Chip/pill height in this app trends 34pt visual, which is under Apple's
  44pt HIG touch-target minimum. This seems to be a house style (compact,
  Uber-like density) rather than a one-off mistake — the correct fix
  recommendation is to expand the invisible hit-test area, not to grow the
  visual chip, to preserve the density the design language is going for.

Linked: [[review_timeline_filter_chips]] — first review record exercising
these conventions.
