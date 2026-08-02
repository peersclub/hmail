# NoMail — Vault Home

Gmail is a backend, not a surface. NoMail reads a mailbox and renders the
things in it that need doing — bills, subscriptions, packages, meetings,
travel, refunds — as ranked, tappable cards, each carrying the link that
resolves it.

- **Repo:** `peersclub/hmail` — local at `/Users/Victor/Projects22/hmail`
- **Stack:** Flutter (iOS-first), Provider, Gmail API (read-only),
  OpenRouter for the AI layer, `url_launcher` for deep links
- **Status (2026-08-02):** running on iPhone and iPad against real Gmail.
  Four tabs (Today · Money · Timeline · Settings), multi-account, an AI audit
  pass, a playbook the app extends by itself, and link routing that opens the
  app you actually have. 367 tests green.

## Map

**Product**
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

## The one-paragraph version

Hand-written rules extract what they recognise; a **learned playbook** handles
shapes the app was taught previously; the AI audits those results, writes the
daily brief, and — for anything still unrecognised — *writes a new recipe* the
app then applies deterministically. Every AI step is optional: with no key,
rules carry the whole load. Everything the AI changed is listed in plain
language under Settings → Processing, and every recipe it wrote can be
inspected, disabled or forgotten under Settings → Knowledge.
