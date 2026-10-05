# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those
roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the
corresponding label string from this table.

## Relationship to the labels already here

`needs-info` and `ready-for-human` are renames of this tracker's earlier
`needs-reproduction` and `ready` labels, so issues already carrying those keep
their history under the new names. Two labels were deliberately left alone
because they mean something narrower:

- `needs-repro-env` - needs the production mail/server pipeline to reproduce, so
  it is not doable on a dev instance. That is a different blocker from waiting on
  the reporter, so it is not folded into `needs-info`.
- `stale` - old item likely referring to behaviour that no longer exists, pending
  review or close. Not the same as `needs-triage`, which is a live item awaiting
  evaluation.

`next` and `in progress` remain the board-position labels and sit alongside
these roles rather than mapping onto them.

Edit the right-hand column to match whatever vocabulary you actually use.
