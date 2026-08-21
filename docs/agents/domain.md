# Domain Docs

How the engineering skills should consume this repo's domain documentation when
exploring the codebase.

This repo is **single-context**, and it already keeps the two records the skills
look for, under its own names. Use these rather than creating a `CONTEXT.md` or a
`docs/adr/` directory alongside them - a second, parallel record is worse than
one that is actually maintained.

## Before exploring, read these

- **`AGENTS.md`**, "Key domain knowledge" - the glossary role. Jurisdictions,
  authorities and Pro coupons, with the reasoning behind each.
- **`README.md`** - the reference tables the glossary points at: Jurisdictions,
  Categories, Authorities, Pro subscriptions, and "Adding more jurisdictions".
- **`docs/DECISIONS.md`** - the decision-record role, in place of `docs/adr/`.
  Cross-cutting engineering decisions that aren't tied to one file or area. Read
  the entries touching the area you're about to work in. It currently holds only
  its own conventions and no entries yet, so expect nothing there until decisions
  start being recorded.

Also read `AGENTS.md`, "Architecture" before changing how the theme loads,
patches, or overrides the host app.

## Recording new decisions

Where a skill would write an ADR under `docs/adr/`, add an entry to
`docs/DECISIONS.md` instead, following the conventions stated at the top of that
file: append new entries at the top, date them, and don't edit past entries
except to mark them superseded and say by what. A decision local to one
file/view/patch belongs as a comment there instead, explaining why.

Numbered ADR filenames don't exist here, so refer to a decision by its date and
heading rather than an `ADR-0007` style identifier.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal,
a hypothesis, a test name), use the term as defined in "Key domain knowledge" and
`README.md`. Don't drift to synonyms those explicitly avoid. This repo overlays a
much larger host app, so host Alaveteli vocabulary matters too: an
`InfoRequest`, an `IncomingMessage`, an authority **tag** driving jurisdiction
rules. Prefer the host's name for a host concept over inventing a theme-local
one.

If the concept you need isn't documented yet, that's a signal - either you're
inventing language the project doesn't use (reconsider) or there's a real gap
(note it for `/domain-modeling`).

## Flag decision conflicts

If your output contradicts an entry in `docs/DECISIONS.md`, surface it explicitly
rather than silently overriding:

> _Contradicts the <date> decision on <heading>, but worth reopening because..._
