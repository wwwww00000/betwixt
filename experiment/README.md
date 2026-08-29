# First Betwixt experiment

## Viewer-style attachment

From the repository root, try the recommended projection over the real source
buffer with:

```sh
nvim -u experiment/attached_init.lua
```

To retain your normal Neovim configuration instead, start it with Betwixt on
the runtime path:

```sh
nvim experiment/sample.lua \
  +'set runtimepath^=.' \
  +'runtime plugin/betwixt.lua'
```

Then run `:BetwixtAttach experiment/review.betwixt.md` in Neovim.

The comments begin as virtual highlighted sections, so ordinary source editing
and `:write` remain untouched. Place the cursor within or near a comment's
range and press `<leader>re` (or run `:BetwixtEdit`) to materialize every
comment as actual lines in the same source buffer. The materialized lines use
the language's `commentstring`; in the Lua fixture they look like this:

```lua
-- ╭─ betwixt · human · open · question · sample.lua:2-3
-- Could this be clearer?
-- ╰─ betwixt
```

Edit source and comment lines with ordinary motions and undo. In this mode,
`:w` validates the frames, passes pure source through Neovim's native write
hooks, writes the sidecar, and keeps the interleaved view open. Run
`:BetwixtVirtual` after saving to return to virtual display, or
`:BetwixtVirtual!` to discard unsaved interleaved edits.
The physical language-comment prefix remains visible so it is clear why the
materialized review text is valid source. The header's author, status, and type
are directly editable; the target range, anchor state, and frame boundary
remain protected.
After a successful write, `<leader>re` toggles back to virtual display as well.
Entering and leaving interleaved mode establishes a fresh undo history so an
old undo entry cannot accidentally restore review text into a normal source
write. This first cut only accepts line-comment `commentstring` values.

The same attachment works in a viewer pane when that pane contains the real
working-file buffer, as CodeDiff and Diffview do for working-tree comparisons:

```vim
:BetwixtAttach /absolute/path/to/review.betwixt.md
```

`BetwixtAttach!` projects comments before their ranges. `:BetwixtRefresh`
reloads the sidecar, and `:BetwixtDetach` removes the projection.

To test side-by-side alignment in CodeDiff with your actual Neovim
configuration, run:

```sh
nvim +'luafile experiment/codediff_init.lua'
```

The launcher creates a baseline commit and a reviewed commit, then opens
`HEAD~` against the clean, editable working buffer whose contents equal `HEAD`.
The reviewed commit adds input validation and an empty-cart branch while
removing legacy service-fee and summary code, producing several addition and
deletion regions. The two stored review anchors remain unchanged across the
revisions so their opposite-side placement is still unambiguous.
The comment is projected on the editable side and an equal-height amber spacer
is placed at the uniquely matching baseline anchor. CodeDiff includes both in
its structural scroll alignment. Press `t` to compare its inline layout;
returning to side-by-side restores the highlighted spacer. The disposable
repository is available as `g:betwixt_codediff_fixture`.

The first source line remains unchanged deliberately. An insertion at the
literal start of a file makes CodeDiff place a filler above line 1; Neovim clips
that virtual row when line 1 is the window topline, producing a viewer-level
one-row offset even with all Betwixt decorations removed.

To test the higher-risk presentation inside the locally installed Diffview,
including contrast against addition highlighting and diff scrolling, use:

```sh
nvim -u experiment/diffview_init.lua
```

The equivalent run with your actual Neovim configuration is:

```sh
nvim +'set runtimepath^=.' \
  +'runtime plugin/betwixt.lua' \
  +'luafile experiment/diffview_init.lua'
```

The launcher creates a disposable Git repository under `/tmp`, commits the
fixture, and inserts a working-tree line above the anchors. This gives the
comments a real green diff hunk, an editable working pane, and a moved-anchor
state without changing the Betwixt repository. Its path is available as
`g:betwixt_diffview_fixture` during the session; treat it as disposable.

## New-comment flow

Visually select the smallest useful source range and run:

```vim
:'<,'>BetwixtComment [type]
```

When no sidecar is attached, the command lazily uses
`<source-file>.betwixt.md`; the file is not created until `:w`. Once attached,
the `<leader>rc` mapping provides the same command for a visual range or the
cursor line. Both paths materialize the comments as syntactic source-language
comments, place the cursor in a new blank body, and enter insert mode. The
optional type defaults to `comment`, status defaults to `open`, and authorship
comes from `setup({ author = ... })`, then `g:betwixt_author`, with a fallback
of `human`:

```lua
require("betwixt").setup({ author = "reviewer" })
```

Use `:w` to persist the new sidecar comment and any ordinary source edits in
the same operation. `:BetwixtVirtual` returns to virtual display after the
write. Before writing, `:BetwixtVirtual!` cancels the new comment and discards
other unsaved interleaved changes. Canceling the first unwritten comment leaves
no sidecar behind.

## Composite-buffer comparison

The earlier physical-line experiment remains available with:

```sh
nvim -u experiment/init.lua
```

The cursor starts inside the first highlighted comment body. Edit it with
ordinary Neovim commands. Source rows are ordinary source text too: `:write`
persists source edits to `sample.lua` and comment-body edits to
`review.betwixt.md` in the same operation. Edits to the comment frame are
rejected, and external changes to either backing file require a reload.

The default projection places each comment after its range. Compare the other
boundary with:

```vim
:BetwixtOpen! experiment/review.betwixt.md
```

The bang selects placement before the range. To exercise the anchor, insert
source lines above a target directly in the projected buffer, use `:write`, and
then run `:BetwixtReload` to refresh the anchor display. The retained fixture
is also an exact-only compatibility case. Newly created comments add one
readable line of context on each side to disambiguate repeated exact excerpts.
Betwixt reports a unique relocated excerpt as `moved`; edited or deleted
targets become `stale`, and repeated targets without one contextual match
become `ambiguous`. Reloading never rewrites the stored range, anchor, or
context.
