---
name: betwixt-comment
description: Add an attributed code-review comment to a repository using its current Betwixt plain-text sidecar convention. Use when asked to record review feedback without modifying the reviewed source; do not use to apply fixes or create threads and replies.
---

# Add A Betwixt Comment

Record one review finding in the same repository as the reviewed code while
preserving a strict comment-versus-change boundary.

## Before Writing

- Confirm the target repository and the user's authority to add review state.
- Read that repository's current Betwixt sidecar example, format note, or test
  fixture. Follow it rather than inventing a competing layout.
- If no current convention exists, ask where the experimental artifact should
  live instead of silently choosing per-file, per-review, or repository-wide
  organization.

## Comment Shape

- Anchor the finding to the smallest useful file and line range. Do not reduce
  a range finding to an arbitrary single-line identity merely because a
  frontend needs one display boundary.
- Preserve enough visible source context to make the target understandable
  under the repository's current experimental convention.
- Under Betwixt's context-assisted convention, copy the exact selected lines
  into `anchor`, the immediately preceding line into `context-before`, and the
  immediately following line into `context-after`. Leave a context block empty
  when the range touches that file boundary.
- Record authorship, status, and note type as visible text, followed by the
  comment body in the user's wording or a faithful concise review statement.
- Add a new comment only. Do not invent a thread, reply relationship, or hidden
  resolution transition.

## Authority And Return

- Do not modify reviewed source, apply a suggested fix, delete another actor's
  note, or claim human acceptance unless separately authorized.
- Keep the sidecar readable without a specialized viewer.
- Report the sidecar path, target file and range, and the exact comment added.
  If the anchor is ambiguous or stale, surface that condition rather than
  guessing silently.
