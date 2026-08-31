# Betwixt

Betwixt is a local-first code-review sidecar project. It keeps review artifacts
as plain text co-located with the repository being reviewed, projects them into
Neovim as line-adjacent sections that can be edited directly, and gives humans
and agents the same bounded operation for adding comments.

The name is a playful use of “between”: review text lives betwixt source lines
in the editing projection while remaining distinct from source code on disk.

## Current Plugin Slice

The first experiment has become a local Neovim plugin while retaining its
synthetic fixtures. The current end-to-end path can:

1. attach an existing one-file plain-text sidecar to its real source buffer;
2. display attributed range comments as highlighted virtual lines;
3. materialize them as source-language comments for ordinary editing;
4. write simultaneous source and review edits to their separate files;
5. create comments from a visual range or the cursor line;
6. lazily create or discover an adjacent per-source sidecar on the first
   `:BetwixtComment`;
7. run materialized source writes through Neovim's native write hooks while
   keeping review lines out of the source file;
8. report context-assisted exact anchors as current, moved, stale, or
   ambiguous;
9. keep a linear sequence of attributed replies under a root comment and mute
   threads whose root status is `resolved`; and
10. preserve side-by-side alignment in the tested CodeDiff case while remaining
   editable in CodeDiff and Diffview working-file panes.

The plugin is still an early working slice, not a settled artifact protocol.
The fixtures under `experiment/` retain comparison cases and known viewer
limitations.

## Accepted Boundaries

- The sidecar is the durable review object; Neovim is its first frontend.
- Review artifacts co-locate with reviewed code and remain ordinary text.
- Status, note type, and authorship remain visible in the artifact rather than
  existing only as UI state.
- A comment may target a range even though the projection must choose one
  visual boundary at which to display it.
- Replies are ordered children of one root comment and inherit its anchor and
  status; replying does not change that status automatically.
- Permission to comment does not grant permission to edit reviewed source.
- No dependency stack, database, hosted service, or generalized protocol has
  been selected.

## Deliberately Deferred

- nested reply trees, stable reply identities, and per-reply status;
- generalized collaboration or forge integration;
- automatic resolution or acceptance transitions;
- automatic anchor migration;
- permanent per-file, per-review, or repository-wide storage organization.

## Current Anchoring Experiment

[`doubt.nvim`](https://github.com/makefinks/doubt.nvim) is relevant prior art
for relocating comments after edits. It supplements the selected source text
with short before-and-after context, prefers one unique contextual or exact
match, and treats missing or ambiguous matches as stale.

Betwixt now records one readable source line before and after new anchors and
uses that context only to disambiguate exact matches. The original range,
anchor, and context remain durable while the projection reports the resolved
range. Older exact-only sidecars remain valid.

The current tests cover insertions and deletions above a target, reordered
functions with identical target text, changed surrounding context around a
unique target, duplicated target-plus-context blocks, and edited or deleted
target text. Exact target text survives ordinary movement and reorder; changing
or deleting the selected text deliberately yields a stale anchor. Automatically
rewriting stored anchors, continuously reclassifying every edit, fuzzy matching
edited targets, and adopting Doubt's broader session model remain out of scope
until use of this smaller approach provides evidence for them.

## Current Reply Experiment

A comment may contain an ordered series of `### Reply` sections. Each reply has
only visible authorship and a body, inherits the root comment's anchor, and is
displayed inside the same highlighted block. `:BetwixtReply` appends a reply to
the nearest projected comment and materializes its body for direct editing.

The root status remains a separate explicit edit. A status of `resolved` mutes
the complete thread with a gray highlight, but adding a reply neither resolves
nor reopens it. Nested replies, reply IDs, timestamps, reactions, per-reply
status, and automatic transitions remain outside this experiment.

## Open Questions

- Does the adjacent `<source-file>.betwixt.md` default remain usable in real
  reviews without prematurely settling repository-wide organization?
- Should a later bounded experiment help recover anchors when the targeted
  lines themselves change, or is an explicit stale state safer?
- Do `status` and `type` earn their place through actual review use?
- Is nearest-comment targeting sufficient for replies when several comments
  share or overlap a range?
- Is after-range display still the right default outside the synthetic cases?
- Is temporary diff rematching during materialized editing acceptable in
  longer CodeDiff sessions?
