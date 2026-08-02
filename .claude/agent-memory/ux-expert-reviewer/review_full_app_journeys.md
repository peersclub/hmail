---
name: review-full-app-journeys
description: UX review of NoMail's end-to-end journeys (first run, errors, empty states, progress, action feedback, nav) across Today/Money/Timeline/Settings/AI/Knowledge, 2026-08-02, excluding backup_screen (owned by concurrent edit)
metadata:
  type: project
---

UX REVIEW RECORD
================
Review ID: UXR-2026-08-02-FullAppJourneys
Component/Flow: Full-app journey audit — first run, error journeys, empty
states, progress states, action feedback, navigation coherence. Screens:
sign_in_screen, shell_screen, today_screen, money_screen, timeline_screen,
settings_screen, scan_screen, processing_screen, ai_screen, knowledge_screen,
insight_card, glass.dart, action_sheet.dart, app_controller.dart.
backup_screen.dart and the backup flow were explicitly OUT OF SCOPE (another
engineer rewriting it concurrently) — do not re-review until that lands.
Platform: iOS (Flutter, Cupertino shell)

UX SCORE: 5/10 — the individual screens are well-crafted (Processing screen's
audit trail, ScanScreen's cost transparency, AI screen's trust framing are
all genuinely good), but the app has one systemic wiring gap that undermines
all of them: `AppController.error` is a single shared field rendered in only
two places (Today's bottom Footnote, Sign-in screen), so most error journeys
that don't happen to end on Today are silently swallowed. This is the exact
same anti-pattern as the reported backup bug, just not yet fixed anywhere else.

ANOMALIES FOUND (see full list returned to orchestrator for fix detail):
1. Sync failures are invisible/unstyled outside Today tab; Settings (where
   Sync Now, Add Account, and Rescan all live) never reads `app.error` at
   all — a failed action there reverts silently to the pre-attempt state.
2. `openAction()` (core/action_launcher.dart) returns `bool` for whether the
   OS actually opened the link, but every call site (action_sheet.dart:22,36;
   app_controller.dart:458) discards it. Pay/Track/Join taps that fail (no
   UPI app, no Zoom app, etc.) produce zero feedback — same failure class as
   the reported backup bug, on the app's single most common action.
3. Money and Timeline screens show no live-sync indicator at all (no header
   badge like Today's `_busyBadge`); Money's empty-state caption never
   distinguishes "still scanning" from "genuinely empty" (today_screen.dart
   and timeline_screen.dart both branch empty-state caption on `syncing`;
   money_screen.dart does not, and doesn't watch phase at all).
4. AI "No key" state (settings_screen.dart, ai_screen.dart) tells a shipped
   end user to add `OPENROUTER_API_KEY` to `.env` — there is no in-app key
   entry UI anywhere, so the stated recovery action is impossible for a real
   user. AI Brief / AI audit are pitched as core value elsewhere (Today's
   brief card, Processing's "AI audit" section) but may be permanently and
   silently unreachable.
5. Sign Out / Exit Demo (settings_screen.dart ~133-153) fires on a single
   untouched tap and actually clears the local insight store
   (`app_controller.dart` `signOut()` calls `_store.clear()`), while the
   lesser actions Remove Account and Rescan Everything both get a
   `CupertinoActionSheet` confirm on the same screen. Inconsistent with the
   app's own established destructive-action pattern.
6. First real sign-in: `signIn()` sets `_phase = AppPhase.syncing` (which
   `nomail_app.dart` renders as the full ShellScreen) *before* awaiting
   `_auth.signIn()`. If the OAuth sheet is cancelled, the user sees a flash
   of the empty main shell, then bounces back to Sign-in with the error.
7. Timeline's active domain filter silently reverts to "All" with no
   message when that domain empties out (`activeFilter` fallback,
   timeline_screen.dart:89-90) — reads as "my tap didn't register."
8. Every `GlassEmptyState` (Today/Money/Timeline/Knowledge) is decorative
   text only — no button. The only path forward is pull-to-refresh, which
   is never hinted at visually except on Today (as prose, not a control).

KEY RECOMMENDATIONS:
1. Give `AppController` a per-surface-safe way to show `error` — at minimum,
   render `app.error` in Settings (Data section) and anywhere else an action
   can fail, styled with `Palette.destructive`, not the neutral `Footnote`.
   This single fix closes items 1, 3 (partially), and the Add-account case.
2. Check `openAction()`'s return value at both call sites; on `false`, fall
   back to the insight's own `openEmailAction` (already in every actions
   list) and/or show an inline destructive-text line — the doc comment in
   action_launcher.dart already promises this fallback, it's just not wired.
3. Add the Sign Out confirm sheet — copy-paste the existing
   `_confirmRescan`/`_confirmRemoveAccount` pattern in the same file.

ACCESSIBILITY STATUS: Not the focus of this pass (see
[[review_timeline_filter_chips]] for the last a11y-focused pass on this
codebase); no new a11y anomalies specifically surfaced here beyond the
existing chip findings.

OVERALL VERDICT: Requires Rework — not on visual craft (which is strong) but
on error/feedback wiring, which is the exact complaint that triggered this
review.

NOTES: The individual screens read as if each was designed carefully in
isolation (Processing's audit trail, ScanScreen's live cost estimate, AI
screen's trust framing are all above-average work) but the *connective
tissue* — "what happens when the thing I just tapped fails" — was not
carried through consistently. See [[convention_nomail_design_system]] for
the new architecture note on `app.error` being a single shared field with
exactly two render sites app-wide; that is the root cause worth fixing once
centrally rather than patching per-screen.
