---
title: NoMail worked example — animated onboarding
tags: [skill, onboarding, nomail]
---

# NoMail worked example

Canonical application of [[SKILL]] in this repo.

## Product thesis

Gmail is a receipts backend. NoMail extracts bills, subscriptions, parcels, and meetings into ranked cards with one-tap actions.

Tagline: **Your inbox, minus the inbox.**

## Flow

```
Boot → !seenOnboarding → OnboardingScreen (3 pages)
     → SignInScreen (Google / Sample Data)
     → first empty→populated sync → MoneyShotScreen
     → Today tab
```

## Pre-auth carousel (3 pages)

| # | Headline | Subtitle | Visual |
|---|----------|----------|--------|
| 1 | Your inbox is a receipts layer | Every bill, renewal, and package already emailed you. | Envelope → stacked insight cards |
| 2 | Bills, subs, parcels — one place | Urgency first. Marketing stays buried. | Staggered glass rows (bill / sub / parcel) |
| 3 | One tap resolves it | Pay, track, or join without digging for the link. | Accent CTA pulse + action chip |

CTAs live after the carousel (or on page 3 footer): Continue with Google, Explore with Sample Data, trust line.

Files:
- `lib/ui/screens/onboarding_screen.dart`
- `lib/ui/onboarding/onboarding_pages.dart`
- Prefs: `seen_onboarding` via `SettingsStore`

## Money-shot reveal

Trigger: `AppController._afterSnapshotUpdate` when `!_hadInsights && !snapshot.isEmpty` → `showMoneyShot = true`.

Content from `BackfillStats`:
- Hero: `annualRecurringDisplay` (e.g. `₹18,400/yr`) with count-up
- Eyebrow: "Hiding in your inbox"
- Body: `headline`
- Chips when counts > 0: bills due, packages, meetings this week
- CTA: "Show my Today" → `dismissMoneyShot()`

File: `lib/ui/screens/money_shot_screen.dart`  
Presented from `ShellScreen` when `showMoneyShot` flips true (root navigator). Inline Today card removed to avoid double celebration.

## Design constraints (NoMail-specific)

- ONE accent: monochrome ink (`Palette.accent`)
- Surfaces: `GlassBackground` / `GlassCard` / `IconBadge`
- Urgency red/orange are text-only — never celebration fills
- Reduced motion: skip count-up and pulses

## Tests

- Carousel on first cold signed-out boot; Skip → SignIn
- Money-shot modal after `enterDemo()`; dismiss hides it
- Reduced-motion shows final annual figure immediately
