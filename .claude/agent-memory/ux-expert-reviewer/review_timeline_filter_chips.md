---
name: review-timeline-filter-chips
description: UX review of Timeline screen's reworked filter-chip row (counts, drag-reorder, spacing) in NoMail, 2026-08-02
metadata:
  type: project
---

UX REVIEW RECORD
================
Review ID: UXR-2026-08-02-TimelineFilterChips
Component/Flow: Timeline screen filter-chip row (`_FilterChips`/`_Chip` in
lib/ui/screens/timeline_screen.dart) — per-domain counts, drag-reorder via
`ReorderableDelayedDragStartListener`, added 6px post-chip spacing.
Platform: iOS (Flutter, Cupertino shell)

UX SCORE: 6/10 — right instincts (counts, persisted order, more air), but the
spacing fix didn't fully land, the drag has zero visual feedback, and touch
target / a11y gaps remain.

ANOMALIES FOUND:
- Filtered-view top spacing is 12px (6px row gap + 6px `_DomainSection`
  padding) vs ~42px for the "All" view (6px + SectionLabel's 26px top pad).
  The exact case the fix targeted (a single active filter, unlabeled section)
  got the *least* breathing room. | Severity: High
- `proxyDecorator: (child, index, animation) => child` — the dragged chip has
  no lift/shadow/scale. Long-press-drag with zero feedback during the drag
  itself undercuts both discoverability and "premium" feel. | Severity: High
- Chip tap target is 34pt (visual == hit box, no padding expansion) vs Apple's
  44pt HIG minimum. | Severity: Medium
- Count opacity is stacked: `secondaryLabel * 0.55` on the inactive chip —
  compounds two contrast reductions. Needs a contrast check against
  `badgeFill` in light mode. | Severity: Medium
- No `Semantics(selected:)` on chips — VoiceOver can't tell active from
  inactive; gesture-only reorder likely has no accessible alternative.
  | Severity: Medium
- Label+count has no separator ("Deliveries4"-adjacent spacing) instead of
  the app's own "·" convention used elsewhere (insight_mapper.dart
  `'${f.source} · ${formatDay(f.date)}'`). | Severity: Low

KEY RECOMMENDATIONS:
1. Fix the filtered-view padding to match the All-view's ~40px gap (one-line
   change, directly fixes the stated crowding bug).
2. Give the drag a visual state (scale ~1.05 + shadow via proxyDecorator) —
   cheap, fixes affordance and premium-feel complaints at once.
3. Expand the chip's hit-test area to 44pt without changing the 34pt visual
   pill.

ACCESSIBILITY STATUS: Needs Improvement (touch target, contrast, VoiceOver
selected-state and reorder-alternative all unverified/likely failing).

OVERALL VERDICT: Approved with Changes.

NOTES: See [[convention_nomail_design_system]] for the monochrome-ink rules
and recurring patterns (badgeFill alpha-stacking, "·" separator convention)
that this review's recommendations lean on.
