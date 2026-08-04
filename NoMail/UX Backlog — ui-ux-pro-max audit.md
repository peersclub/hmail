# UX Backlog — ui-ux-pro-max audit (2026-08-04)

Source: `ui-ux-pro-max` App-UI rule database (Apple HIG / Material / WCAG) checked against the actual codebase. Ordered by the skill's priority tiers. Each item lists the violated rule and the code anchor.

## P1 — Accessibility (CRITICAAL tier) — the app is largely invisible to VoiceOver

1. **`GlassRow` is a `GestureDetector`, not a button.** One `Semantics` widget exists in the entire UI (timeline chips). Every insight row, settings row, account row announces as plain text — no button trait, no hint, no action. *Rule: `aria-labels`/`voiceover-sr`, touch semantics.* → Fix in ONE place: `glass.dart:350` — wrap the tappable path in `Semantics(button: true, label: '<title>, <subtitle>')`; same for `_actionRow` (backup) and the account rows.
2. **Icon-only buttons have no labels.** WebView ↗ (open outside), Done, Remove, chips. *Rule: icon-only buttons need `accessibilityLabel`.* → `Semantics(label:)` or `Tooltip`-equivalent on each.
3. **Dynamic Type untested; layouts will truncate.** Flutter scales `fontSize` automatically, but the UI is full of `maxLines: 1` + fixed 36–38pt avatar/badge boxes — at AX sizes text ellipsizes instead of wrapping. *Rule: `dynamic-type` — avoid truncation as text grows.* → Audit at largest AX size; relax `maxLines`, let rows grow, min-height not fixed-height.
4. **Contrast unverified on glass.** 13pt `secondaryLabel` captions sit on blurred translucent cards; 4.5:1 not confirmed in either theme. *Rule: `color-contrast`, `color-dark-mode` (test dark separately).* → Measure worst-case card/backdrop combos; darken `secondaryLabel` or raise card opacity if failing.

## P2 — Touch & interaction (CRITICAL tier)

5. **Zero press feedback on the app's most-used control.** Tapping a `GlassRow` gives no visual response until the sheet opens. *Rules: `press-feedback`, `tap-feedback-speed` (<100ms), `scale-feedback`.* → `onTapDown` highlight (Cupertino-style: background `Palette.badgeFill` flash or 0.55 opacity), no layout shift; one change in glass.dart covers the whole app.
6. **Sub-44pt touch targets.** WebView ↗ is 34×34 (`web_view_screen.dart:298`); feedback-bar buttons use `minimumSize: Size.zero` (:536, :607). *Rule: `touch-target-size` 44×44pt.* → Bump minimums / add padding; visual size can stay small.
7. **Haptics only on timeline chips.** *Rule: `haptic-feedback` for confirmations.* → Add `HapticFeedback.lightImpact` on: backup success, restore applied, account connected, money-shot celebration. Nowhere else (avoid overuse).

## P3 — Performance & perceived speed (HIGH tier)

8. **Spinners where skeletons belong.** First scan runs minutes; Today/Money show a spinner + one line. *Rule: `progressive-loading` — skeleton/shimmer for >1s.* → Glass skeleton rows (3–4 shimmering `GlassRow` silhouettes) under the live `activityLine` during an empty-snapshot sync.
9. **Timeline isn't virtualized and rows lack keys.** All domain sections build eagerly; only 1 `ValueKey` in the tree (chips). *Rules: `virtualize-lists` (50+ items), Flutter stack: keys for list items.* → Move sections into `SliverList`s; `ValueKey(insight.id)` per row. Matters once a real inbox yields 200+ insights.

## P7 — Motion (MEDIUM tier)

10. **Reduced Motion is ignored app-wide** (0 references). Money hero runs a 700ms count-up; money-shot celebration animates. *Rules: `reduced-motion` (HIGH severity), duration ≤400–500ms.* → Gate via `MediaQuery.disableAnimationsOf(context)`: skip count-up (show final value), simplify celebrations; trim hero to ≤500ms for everyone.

## P4/P8 — Style & feedback polish (MEDIUM)

11. **Formal empty-state action slot.** `GlassEmptyState` has no action param; screens bolt `ScanActionButton` beneath. → Add optional `action:` slot (also closes old audit #9).
12. **AI screen's impossible instruction** (old audit #4, still open): "add OPENROUTER_API_KEY to .env" is dead copy on a phone. → Product call: in-app key field (SecureStorage) or honest "not available in this build".
13. **Icon family discipline check.** Filled/outline Cupertino icons mix at the same hierarchy in places (cloud vs cloud_fill is semantic ✓; sweep the rest once).

## P9 — Navigation (HIGH tier, roadmap-scale)

14. **No deep links.** Notification taps only foreground the app; no screen is addressable. *Rule: `deep-linking` — key screens reachable for notifications.* → Route names + `onGenerateRoute`; make the daily-brief notification open Today, an action notification open its insight's sheet.

## Already compliant (verified ✓)
Tabular figures on amounts; 4pt spacing rhythm; one primary CTA per screen; bottom-nav ≤5 with labels (native CNTabBar); confirmation before destructive actions; errors near controls with recovery (this session's journey work); in-flow feedback (no overlay toasts); state preservation across tabs (IndexedStack); safe-area handling via `MediaQuery.paddingOf` + `kDockClearance`.

## Suggested execution waves
- **Wave 1 (one sitting, huge leverage):** #1 #2 #5 #6 — GlassRow semantics + press feedback + target sizes + labels. Mostly `glass.dart`.
- **Wave 2:** #7 haptics, #10 reduced motion, #8 skeletons.
- **Wave 3:** #9 virtualization+keys, #3 Dynamic-Type layout audit, #4 contrast pass, #11.
- **Wave 4 (product calls first):** #12 AI key, #14 deep links.

Related: [[Development Log]], [[Roadmap]]
