# NoMail — Vault Home

Gmail is a backend, not a surface. NoMail reads a mailbox and renders the
things in it that need doing — bills, subscriptions, packages, meetings,
travel, refunds — as ranked, tappable cards, each carrying the link that
resolves it.

- **Repo:** `peersclub/hmail` — local at `/Users/Victor/Projects22/hmail`
- **Stack:** Flutter (iOS-first), Provider, Gmail API (read-only),
  OpenRouter for the AI layer, `url_launcher` for deep links
- **Status (2026-08-05):** running on iPhone and iPad against real Gmail.
  Four tabs (Today · Money · Timeline · Settings), multi-account, an AI audit
  pass, a playbook the app extends by itself, and link routing that opens the
  app you actually have. Now also **price-hike detection**, proactive
  renewal/bill/return alerts, per-insight corrections, and a pre-scan cost
  estimate priced from OpenRouter's live catalog. 475 tests green.
- **Biggest open risk:** every extractor guard was written against fixtures and
  reasoning. No real-inbox tuning round has happened yet — see [[Roadmap]].

## Map

**Product**
- [[PRD]] — the flow-level spec: user jobs, every core flow as a diagram,
  screen states, trust surfaces, and the open decisions that need a product
  call rather than a technical one
- [[One App Vision]] — the north star: 14 life domains, iOS surfaces, the
  agent layer, competitive position, phased roadmap
- [[Requirements]] — what the product must do
- [[Roadmap]] — what is done, what is next

**Engineering**
- [[Architecture]] — current structure, the sync pipeline, the learned
  playbook, and the gotchas worth knowing before editing
- [[Actions API]] — how an insight becomes a tappable action
- [[Settings Plan]] — Settings as the trust surface, and why each control is
  a paid-tier feature
- [[Backup & Restore]] — iCloud and Google Drive backup
- [[Development Log]] — dated record of every session

**Skills** (reusable across apps; Cursor mirror under `~/.cursor/skills/`)
- [[Skills/animated-onboarding/SKILL]] — first-run carousel + post-value
  money-shot reveal; see also [[Skills/animated-onboarding/reference]] and
  [[Skills/animated-onboarding/nomail-worked-example]]

## The one-paragraph version

Hand-written rules extract what they recognise; a **learned playbook** handles
shapes the app was taught previously; the AI audits those results, writes the
daily brief, and — for anything still unrecognised — *writes a new recipe* the
app then applies deterministically. Every AI step is optional: with no key,
rules carry the whole load. Everything the AI changed is listed in plain
language under Settings → Processing, and every recipe it wrote can be
inspected, disabled or forgotten under Settings → Knowledge.

Three layers of correction sit on top, each one a different party being allowed
to be wrong: the AI audit drops insights the rules misread, the user's
**corrections** drop what the AI also missed, and **link feedback** flags
recipes whose URLs go nowhere useful. All three are visible and reversible in
Settings, and none of them delete mail.
