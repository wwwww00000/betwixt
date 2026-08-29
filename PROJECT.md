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
8. report exact anchors as current, moved, stale, or ambiguous; and
9. preserve side-by-side alignment in the tested CodeDiff case while remaining
   editable in CodeDiff and Diffview working-file panes.

The plugin is still an early first slice, not a settled artifact protocol.
The fixtures under `experiment/` retain comparison cases and known viewer
limitations.

## Accepted Boundaries

- The sidecar is the durable review object; Neovim is its first frontend.
- Review artifacts co-locate with reviewed code and remain ordinary text.
- Status, note type, and authorship remain visible in the artifact rather than
  existing only as UI state.
- A comment may target a range even though the projection must choose one
  visual boundary at which to display it.
- Permission to comment does not grant permission to edit reviewed source.
- No dependency stack, database, hosted service, or generalized protocol has
  been selected.

## Deliberately Deferred

- threads and replies;
- generalized collaboration or forge integration;
- a settled resolution or acceptance model;
- automatic anchor migration;
- permanent per-file, per-review, or repository-wide storage organization.

## Potential Anchoring Experiment

[`doubt.nvim`](https://github.com/makefinks/doubt.nvim) is relevant prior art
for relocating comments after edits. It supplements the selected source text
with short before-and-after context, prefers one unique contextual or exact
match, and treats missing or ambiguous matches as stale.

A possible Betwixt experiment is to add similarly readable surrounding context
to the sidecar and use it only to disambiguate moved exact anchors. The original
range and anchor would remain durable, while the projection reports the resolved
range. Automatically rewriting stored anchors, continuously reclassifying every
edit, and adopting Doubt's broader session model remain out of scope unless use
of the simpler approach provides evidence for them. This is a candidate future
experiment, not committed current work.

## Open Questions

- Does the adjacent `<source-file>.betwixt.md` default remain usable in real
  reviews without prematurely settling repository-wide organization?
- Is the current exact excerpt anchor adequate in real reviews where the
  targeted lines themselves change?
- Do `status` and `type` earn their place through actual review use?
- Is after-range display still the right default outside the synthetic cases?
- Is temporary diff rematching during materialized editing acceptable in
  longer CodeDiff sessions?
