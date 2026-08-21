# Issue tracker: GitHub

Issues and specs live as GitHub issues in this repo, `openaustralia/righttoknow`.
Use the `gh` CLI, which infers the repo from `git remote -v` when run inside this
clone.

The Alaveteli fork this theme is loaded into
([openaustralia/alaveteli](https://github.com/openaustralia/alaveteli)) has
GitHub Issues **disabled**, so issues about the host app are tracked here as
well. Branch names in that repo carry the issue number with an `rtk` prefix, e.g.
`feature/rtk1045-ruby-3.4.10` is issue #1045 here; branches in this repo use the
bare number, e.g. `feature/1045-ruby-3.4.10`.

## Drafting, not creating

OAF agent convention, and it governs everything below: GitHub issues have no
draft state, so don't create one directly. Draft the title and body for the human
to file themselves, unless they have explicitly asked you to create it this
time. The same care applies to comments and label changes on other people's
issues. Reading and listing need no such ceremony.

## Conventions

- **Create an issue** (only when the human has asked you to file it):
  `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line
  bodies, and fill in the org-level issue form from `openaustralia/.github` under
  `.github/ISSUE_TEMPLATE/` rather than writing a freeform body.
- **Read an issue**: `gh issue view <number> --comments`
- **List issues**:
  `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`
  with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` /
  `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external
PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using
the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for
  the diff.
- **List external PRs for triage**:
  `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`
  then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`,
  or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label` /
  `--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be
either - resolve with `gh pr view 42` and fall back to `gh issue view 42`. A
number in a *host app* branch or commit message is an issue here, not a PR.

Note that PRs against the host Alaveteli fork live in that repo, so reviewing
theme and host changes for one piece of work can mean two PRs in two repos
against one issue here.

## When a skill says "publish to the issue tracker"

Draft a GitHub issue and hand the title and body to the human to file - see
"Drafting, not creating" above.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as
tickets. Creating any of these goes through "Drafting, not creating" first.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes /
  Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on
  the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a
  task list in the map body and put `Part of #<map>` at the top of the child
  body. Labels: `wayfinder:<type>`
  (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is
  assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies** - the canonical,
  UI-visible representation. Add an edge with
  `gh api --method POST repos/openaustralia/righttoknow/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`,
  where `<blocker-db-id>` is the blocker's numeric **database id**
  (`gh api repos/openaustralia/righttoknow/issues/<n> --jq .id`, _not_ the
  `#number` or `node_id`). GitHub reports
  `issue_dependencies_summary.blocked_by` (open blockers only - the live gate).
  Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>`
  line at the top of the child body. A ticket is unblocked when every blocker is
  closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`,
  scoped to the map's sub-issues / task list), drop any with an open blocker
  (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the
  `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me` - the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then
  `gh issue close <n>`, then append a context pointer to the map's
  Decisions-so-far. Where the answer is a cross-cutting decision rather than a
  one-off, add it to `docs/DECISIONS.md` too and link that from the map.
