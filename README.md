# Betwixt

Betwixt is an early local-first Neovim code-review plugin. Review comments live
in a plain-text sidecar beside the reviewed source, appear as highlighted
line-adjacent sections, and can temporarily become ordinary syntactic comment
lines for direct editing.

The source buffer remains the real working-file buffer. In materialized mode,
one `:w` separates and writes source edits to the source file and review edits
to the sidecar.

## Installation

Load the current main branch with lazy.nvim:

```lua
{
  "wwwww00000/betwixt",
  main = "betwixt",
  cmd = { "BetwixtAttach", "BetwixtComment", "BetwixtOpen" },
  opts = {
    author = "reviewer",
  },
}
```

The complete setup surface is:

```lua
require("betwixt").setup({
  author = "reviewer", -- defaults to g:betwixt_author, then "human"
  mappings = {
    comment = "<leader>rc", -- Normal: current line; Visual: selected lines
    edit = "<leader>re", -- toggle virtual and materialized comments
  },
})
```

Set either mapping to `false` to disable it. Betwixt has no required plugin
dependencies. Its CodeDiff alignment support activates only when CodeDiff is
already present. The mappings are installed only after a sidecar is attached;
the first review can begin with `:BetwixtComment`.

## Sidecar

An existing sidecar currently targets one source file relative to its own
directory:

```markdown
# Betwixt review

file: sample.lua

## Comment

range: 2-3
author: human
status: open
type: question
anchor:
      local subtotal = value
      return subtotal
context-before:
    local function total(value)
context-after:
    end
body:
Could this be clearer?
```

`anchor` is the exact selected source excerpt. New comments also retain one
immediately adjacent line in each context block; an empty block records that
the range touched that file boundary. The context is only a tie-breaker between
repeated exact excerpts. If the context changes but the anchor remains unique,
the anchor still resolves.

A uniquely relocated excerpt is displayed as moved. If the selected text is
edited or deleted, it is displayed as stale. Repeated excerpts remain
ambiguous unless exactly one has the recorded context. Older exact-only
sidecars remain valid, and Betwixt does not rewrite stored ranges, anchors, or
context automatically.

## Workflow

Open a saved source file and create the first comment directly:

```vim
:[range]BetwixtComment [type]
```

When no review is attached, the command lazily targets an adjacent
`<source-file>.betwixt.md` sidecar. Nothing is created merely by opening or
editing the source. The sidecar is created by the first `:w`; discarding the
pending comment with `:BetwixtVirtual!` leaves no file behind. A later
`:BetwixtComment` discovers and reuses the same default sidecar.

To use an existing sidecar at another path, attach it explicitly:

```vim
:BetwixtAttach path/to/review.betwixt.md
```

Comments initially appear as virtual highlighted lines. Then:

- Press `<leader>re` or run `:BetwixtEdit` to materialize comments.
- Edit comment bodies or their visible author, status, and type metadata.
- Visually select source lines and press `<leader>rc` to add a range comment.
- Press `<leader>rc` in Normal mode to comment on the cursor line.
- Use `:BetwixtComment risk` to specify a type explicitly.
- Use `:w` to write the source and sidecar together.
- Use `:BetwixtVirtual` to return to virtual display.
- Use `:BetwixtVirtual!` to discard unsaved materialized changes.

Materialized review lines use the current filetype's real line-comment syntax,
such as `-- ` in Lua. This keeps the temporary source buffer parseable by
Tree-sitter, LSPs, and formatters while the write hook keeps those lines out of
the source file. Materialized editing currently requires a line-comment
`commentstring`. During `:w`, Betwixt temporarily presents pure source to
Neovim's native write path, so normal `BufWritePre` formatting and
`BufWritePost` hooks run without seeing review lines. It then restores the
interleaved view. The sidecar is written only after the native source write
succeeds, so a rejected source write leaves the sidecar untouched and the
pending buffer editable.

Run `:help betwixt` for the command reference.

## Status

This is an early plugin slice, tested with Neovim 0.12. The retained fixtures
cover lazy first-comment creation, native write hooks and failure recovery, Lua,
JavaScript, and Python comment syntax, ordinary attachment, simultaneous source
and sidecar writes, context-assisted anchoring under common source edits,
CodeDiff alignment, and Diffview editing.

Multi-file artifact organization, automatic anchor migration, threads,
replies, and hosted collaboration remain deliberately outside the current
slice.

## Development

The focused checks are standalone Neovim scripts under `tests/`. The richer
interactive launchers and their known diff-view limitations are documented in
`experiment/README.md`. Headless viewer tests exercise actual CodeDiff and
Diffview buffers, windows, virtual rows, materialized review lines, writes, and
screen-row alignment. Terminal color rendering, flicker, and subjective
interaction still require an interactive check.

## License

Betwixt is available under the MIT License. See `LICENSE`.
