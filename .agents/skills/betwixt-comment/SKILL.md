---
name: betwixt-comment
description: Add an attributed root comment or linear reply to a repository using its current Betwixt plain-text sidecar convention. Use when asked to record review feedback without modifying the reviewed source; do not use to apply fixes, change resolution state, or invent nested threads.
---

# Add Betwixt Review Feedback

Record one root review comment or one reply in the same repository as the
reviewed code while preserving a strict comment-versus-change boundary.

## Before Writing

- Confirm the target repository and the user's authority to add review state.
- Discover any existing Betwixt sidecar targeting the reviewed source and
  follow the repository's current convention rather than inventing a competing
  layout.
- If none exists and one source file is unambiguous, use Betwixt's current
  adjacent `<source-file>.betwixt.md` default. Ask before choosing when the
  target file or artifact location is ambiguous.
- Read the current source and sidecar before writing. Do not modify the reviewed
  source as part of this operation.

## Root Comment

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
- Append a new `## Comment` without rewriting or deleting existing review
  content. New root comments normally begin with status `open`.

## Linear Reply

- Identify the intended root comment from the user's request and the visible
  sidecar fields. If more than one root is plausible, ask rather than attaching
  the reply by proximity alone.
- Append one `### Reply` after the root's existing replies. A reply contains
  only visible `author` and `body` fields and inherits the root's anchor and
  status.
- Do not add reply anchors, ranges, statuses, types, IDs, or timestamps. Do not
  nest replies or infer a reply-to relationship between replies.
- Replying does not resolve, reopen, or otherwise change the root comment's
  status, including when the root is already `resolved`.

## Authority And Return

- Do not modify reviewed source, apply a suggested fix, delete another actor's
  note, change resolution state, or claim human acceptance unless separately
  authorized.
- Keep the sidecar readable without a specialized viewer.
- Report the sidecar path, the root target file and range, whether a root or
  reply was added, and the exact text added. If the anchor is ambiguous or
  stale, surface that condition rather than guessing silently or rewriting it.
