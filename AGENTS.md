# Betwixt Agent Instructions

## Orientation

Read `PROJECT.md` before changing the repository. It owns the current project
boundary, current plugin slice, deferred work, and open questions.

## Project Boundary

Betwixt owns a repository-co-located plain-text code-review sidecar, its first
Neovim editing and display projection, and bounded agent operations for adding
root comments and linear replies. Reviewed repositories continue to own their
source code.

When asked only to review or comment, do not modify the reviewed source. Keep
comment authority, claims that a finding was addressed, and human acceptance as
separate actions.

## Current Phase

Active feature development is paused while the current plugin and sidecar are
used in real reviews. Prefer recording concrete trial friction and fixing
demonstrated failures over expanding the artifact or interaction model.

## Slice Guardrails

- Preserve the thinnest working end-to-end path and add only the smallest
  representative case for any failure observed during the pilot.
- Keep the sidecar readable and editable as ordinary text without Neovim or an
  agent harness.
- Prefer directly editable highlighted line sections over popup comment cards.
- Treat displayed lines as projection positions rather than automatically as
  durable note identities.
- Keep storage organization, range placement, and stale-anchor behavior
  experimental until the live trial provides evidence.
- Keep replies linear. Do not add nested threads, stable reply identities, a
  database, hosted collaboration, automatic synthesis, or source write-back
  without evidence from the live trial.

## Project Skill

Use `.agents/skills/betwixt-comment/SKILL.md` when asked to add a root review
comment or linear reply through the current Betwixt sidecar convention. The
skill does not authorize code changes, status transitions, or a nested reply
model.
