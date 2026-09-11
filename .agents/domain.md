# Domain Docs

How the engineering skills should consume this repo's domain documentation when
exploring the codebase.

This repo is **single-context**. The glossary role is played by existing files
under their own names - use those rather than creating a `CONTEXT.md` alongside
them, since a second, parallel record is worse than one that is actually
maintained. Decision records are standard ADRs, but they live in `doc/adr/`
(singular `doc/`, matching Alaveteli's convention) because `docs/` is reserved
for application-related material.

## Before exploring, read these

- **`AGENTS.md`**, "Key domain knowledge" - the glossary role. Jurisdictions,
  authorities and Pro coupons, with the reasoning behind each.
- **`README.md`** - the reference tables the glossary points at: Jurisdictions,
  Categories, Authorities, Pro subscriptions, and "Adding more jurisdictions".
- **`doc/adr/`** - the decision records. Cross-cutting engineering decisions
  that aren't tied to one file or area. Read the ADRs touching the area you're
  about to work in.

Also read `AGENTS.md`, "Architecture" before changing how the theme loads,
patches, or overrides the host app.

## Recording new decisions

Where a skill would write an ADR under `docs/adr/`, write it under `doc/adr/`
instead - same format, sequential `0001-slug.md` numbering, referenced as
`ADR-0001` style identifiers. A decision local to one file/view/patch belongs
as a comment there instead, explaining why.

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

If your output contradicts an ADR in `doc/adr/`, surface it explicitly
rather than silently overriding:

> _Contradicts ADR-NNNN (<title>), but worth reopening because..._
