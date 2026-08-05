---
title: Animated Onboarding — Reference
tags: [skill, onboarding, motion]
---

# Reference

Companion to [[SKILL]]. App-agnostic tokens and anti-patterns.

## Page archetypes

| Archetype | Headline shape | Visual |
|-----------|----------------|--------|
| Reframe | "X is really Y" | Object transforms into the new surface |
| Inventory | "Everything that matters, one place" | Staggered rows / chips of domains |
| Resolve | "One tap finishes it" | CTA + action chip pulse |

Never mix archetype jobs on one page.

## Motion tokens

| Token | Duration | Curve | Use |
|-------|----------|-------|-----|
| enter | 300–400ms | ease-out | Page content appear |
| page | 250–300ms | ease-in-out | Horizontal page change |
| stagger | +60ms each | ease-out | List/row cascade |
| count | ≤450ms | easeOutCubic | Number reveal |
| pulse | 900ms reverse | ease-in-out | Soft CTA breathe (optional, gated) |
| exit | 150–200ms | ease-in | Dismiss |

Hard caps: no animation >500ms except optional ambient pulse that is purely decorative and must stop under reduced motion.

## Reduced motion

```
if (disableAnimations) {
  show final opacity/position/number immediately;
  do not start controllers or loops;
}
```

Flutter: `MediaQuery.disableAnimationsOf(context)`
SwiftUI: `@Environment(\.accessibilityReduceMotion)`
CSS: `@media (prefers-reduced-motion: reduce)`

## Persistence shape

```
key: seen_onboarding   // bool, default false
set true on: Skip | last-page Continue | equivalent
```

Do not bury this inside a large settings blob whose schema churns — a dedicated prefs key is enough.

## A11y checklist

- Each page announces its headline as a heading
- Page dots are decorative (`ExcludeSemantics`) or expose "Page N of M"
- Skip / Continue are buttons with labels
- Icon-only dismiss has an accessibility label
- Touch targets ≥44pt even if visual control is smaller

## Anti-patterns

| Smell | Fix |
|-------|-----|
| 5+ carousel pages | Cut to 3 beats |
| Feature matrix on page 1 | Move to Settings / empty states |
| Fake stats in the reveal | Wait for real data or skip reveal |
| Inline card + full-screen both celebrate | Keep one |
| Auto-advance pages | Let the user swipe |
| Paywall as page 3 | Auth/value first; paywall later |
| Second accent color for "celebration" | Opacity / weight on the existing accent |
