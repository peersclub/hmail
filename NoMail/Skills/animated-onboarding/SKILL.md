---
name: animated-onboarding
description: >-
  Design and implement first-run animated onboarding: pre-auth story carousel
  (max 3 beats) plus a post-value conversion reveal (money-shot). Use when the
  user asks for onboarding, first-run, welcome carousel, intro screens, or a
  money-shot / first-scan reveal. Works across Flutter, SwiftUI, and React.
---

# Animated Onboarding

Source of truth: this vault note. Cursor mirror: `~/.cursor/skills/animated-onboarding/`.
Worked example: [[nomail-worked-example]]. Motion tokens: [[reference]].

## When to use

- New app needs a first-run story before auth
- Existing static welcome should become an animated carousel
- First successful data load should celebrate with a full-screen reveal
- User says "onboarding", "first 60 seconds", "welcome screens", "money shot"

## Core model

```
Boot → seenIntro? → Carousel (once) → Auth CTA
Auth → first empty→populated value → MoneyShot reveal → Home
```

Two moments, not one tour:

1. **Story** (pre-auth) — why this product exists. Max 3 pages.
2. **Proof** (post-value) — what we found for *you*. One full-screen reveal.

Feature checklists and permission walls are not onboarding. Skip exists on every carousel page.

## Procedure

### 1. Extract the product thesis

One sentence the brand owns. If removing the logo still reads as generic productivity, rewrite.

NoMail: "Your inbox, minus the inbox."

### 2. Write three story beats

| Beat | Job | Anti-pattern |
|------|-----|--------------|
| 1 | Reframe the problem | Feature list |
| 2 | Show the new surface | Screenshot dump |
| 3 | Promise the action | Paywall |

Each page: one headline, one short subtitle, one animated visual. No cards-in-hero. No stat strips.

### 3. Define the conversion reveal

Trigger: first time empty state becomes populated (not every sync, not cached boot).
Content: the most impressive real number + one sentence headline + optional secondary chips.
CTA: enter the home surface. Dismissible. Never block forever.

### 4. Motion

See [[reference]]. Defaults:

- Enter ≤400ms ease-out; page transition ≤300ms
- Stagger list items +60ms
- Count-up ≤450ms easeOutCubic
- Gate all loops/count-ups with reduced-motion → show final frame
- One light haptic on Continue / reveal open — nowhere else

### 5. Persist

`seen_onboarding` (or equivalent) in local prefs. Mark on Skip **or** last-page Continue. Cold boot after that goes straight to auth/home.

### 6. Implement (platform notes)

| Stack | Carousel | Reveal |
|-------|----------|--------|
| Flutter | `PageView` + `PageController`, native `AnimationController` | Full-screen route via root navigator |
| SwiftUI | `TabView(.page)` | `.fullScreenCover` |
| React | CSS scroll-snap or swipe lib | Modal route |

No Rive/Lottie/`flutter_animate` unless the design system already depends on them. Prefer composing existing tokens (glass, accent, type).

### 7. Verify (incremental)

One failing test per beat:

1. First cold signed-out boot shows page 1
2. Skip / Continue sets seen flag and lands on auth
3. First populate sync presents reveal; dismiss hides it
4. Reduced-motion still shows final values

## Checklist before shipping

- [ ] ≤3 pre-auth pages
- [ ] Skip on every page
- [ ] Auth CTAs only on last page (or after carousel)
- [ ] Reveal uses real user data, not placeholders
- [ ] Reduced motion respected
- [ ] VoiceOver: page titles, Skip, Continue labeled
- [ ] 44pt hit targets on controls
- [ ] No second celebration (inline card + modal)

## Do not

- Tour every tab/feature
- Ask for push/contacts/tracking before value
- Use decorative purple glow / multi-layer shadows as the visual idea
- Animate longer than 500ms for count-ups
- Re-show the carousel after the user completed it
