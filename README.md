# Betwixt

Betwixt is an early local-first Neovim code-review plugin. Review comments live
in a plain-text sidecar beside the reviewed source, appear as highlighted
line-adjacent sections, and can temporarily become ordinary syntactic comment
lines for direct editing.

The source buffer remains the real working-file buffer. In materialized mode,
one `:w` separates and writes source edits to the source file and review edits
to the sidecar.

## Installation

Betwixt currently has no remote release. Load a local checkout with lazy.nvim:

```lua
{
  dir = "/path/to/betwixt",
  name = "betwixt",
  main = "betwixt",
  cmd = { "BetwixtAttach", "BetwixtOpen" },
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
already present.

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
body:
Could this be clearer?
```

The exact source excerpt is the current experimental anchor. A uniquely moved
excerpt is displayed as moved; missing or repeated excerpts are displayed as
stale or ambiguous. Betwixt does not rewrite stored ranges automatically.

## Workflow

Open the source file, then attach its sidecar:

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
the source file.

Run `:help betwixt` for the command reference.

## Status

This is an early plugin slice, tested with Neovim 0.12. The retained
fixtures cover ordinary attachment, simultaneous source and sidecar writes,
new-comment creation, CodeDiff alignment, and Diffview editing.

Creating the first sidecar, multi-file artifact organization, automatic anchor
migration, threads, replies, and hosted collaboration remain deliberately
outside the current slice.

## Development

The focused checks are standalone Neovim scripts under `tests/`. The richer
interactive launchers and their known diff-view limitations are documented in
`experiment/README.md`.

## License

Betwixt is available under the MIT License. See `LICENSE`.
