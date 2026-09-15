# Betwixt

Betwixt is an early local-first Neovim code-review plugin. Review comments live
in a plain-text sidecar under the project’s `.betwixt/` directory, appear as
highlighted line-adjacent sections, and can temporarily become syntactic
comment sections for direct editing.

The source buffer remains the real working-file buffer. In materialized mode,
one `:w` separates and writes source edits to the source file and review edits
to the sidecar.

## Installation

Load the current main branch with lazy.nvim:

```lua
{
  "wwwww00000/betwixt",
  main = "betwixt",
  cmd = {
    "BetwixtAttach", "BetwixtComment", "BetwixtOpen",
    "BetwixtReply", "BetwixtReload", "BetwixtRefresh",
  },
  keys = {
    { "<leader>rc", "<cmd>BetwixtComment<cr>", desc = "Comment on current line" },
    { "<leader>rc", ":BetwixtComment<cr>", mode = "x", desc = "Comment on selection" },
    { "<leader>rr", "<cmd>BetwixtReload<cr>", desc = "Reload or attach review" },
  },
  opts = {
    author = "reviewer",
  },
}
```

The `keys` entries load the plugin on first use, so commenting and reopening a
review work before attachment. The Visual mapping uses `:` to retain the
selected range.

The complete plugin setup surface is:

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
already present. The plugin's own mappings are installed after attachment;
the lazy.nvim `keys` entries above make comment creation available beforehand
and add a global reload binding. If you change or disable `<leader>rc`, update
both `keys` entries and `mappings.comment` to match.

### Recommended bindings

| Binding | Mode | Action |
| --- | --- | --- |
| `<leader>rc` | Normal / Visual | Add a comment on the cursor line / selected source range, in either display mode |
| `<leader>re` | Normal, after attachment | Toggle virtual display and interleaved editing; write pending edits first |
| `<leader>rr` | Normal | Reload the sidecar, attaching the default review if present |
| `:w` | Command | Save source edits, comment edits, and deleted threads |

`<leader>rc` and `<leader>rr` work before attachment with the lazy.nvim example
above. With another loader, call `setup` and add the equivalent global mappings
shown in [`:help betwixt-setup`](doc/betwixt.txt). Reload is deliberately mapped
without `!`; use `:BetwixtReload!` explicitly to discard unsaved interleaved
changes. `:BetwixtReply` still starts from virtual mode: write your edits and
press `<leader>re` first.

## Sidecar

Each sidecar targets one source file relative to its own directory. For
`sample.lua` at the project root, `.betwixt/sample.lua.betwixt.md` contains:

```markdown
# Betwixt review

file: ../sample.lua

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

### Reply

author: reviewer
body:
The intermediate name could describe the unit.
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

Replies form one ordered, non-nested conversation under their root comment.
They contain only an author and body, inherit the root anchor and status, and
do not change that status automatically. A root status of `resolved` gives the
whole thread a muted gray background.

## Workflow

### Regular source buffer

Open a saved source file and create the first comment directly:

```vim
:[range]BetwixtComment [type]
```

When no review is attached, the command lazily targets
`.betwixt/<source-relative-path>.betwixt.md` at the nearest Git worktree root
(beside `.git`, including worktrees), or under `cwd` outside Git. For example,
`src/app.lua` uses `.betwixt/src/app.lua.betwixt.md`. Outside Git, files outside
`cwd` use `.betwixt/_external/<absolute-source-path>.betwixt.md`.
The sidecar’s `file:` field stays relative to its own directory. Nothing is
created merely by opening or editing the source. The sidecar is created by the
first `:w`; discarding the pending comment with `:BetwixtVirtual!` leaves no
file behind. A later
`:BetwixtComment` discovers and reuses the same default sidecar.

Use `:BetwixtAttach` without arguments to discover the default sidecar.
`:BetwixtReload` and `:BetwixtRefresh` also attach it if present, and otherwise
leave an unattached buffer alone. Reloading an attached review returns to virtual
mode; unsaved interleaved edits require `:w` or an explicit `!` to discard them.

Existing adjacent sidecars are not moved automatically. To use a sidecar at
another path, attach it explicitly:

```vim
:BetwixtAttach path/to/review.betwixt.md
```

Comments initially appear as virtual highlighted lines. Then:

- Press `<leader>re` or run `:BetwixtEdit` to materialize comments.
- Edit comment bodies or their visible author, status, and type metadata.
- Visually select source lines and press `<leader>rc` to add a range comment.
- Press `<leader>rc` in Normal mode to comment on the cursor line.
- Use `:BetwixtComment risk` to specify a type explicitly.
- Place the cursor in or near a comment's range and use `:BetwixtReply` to
  append a reply and begin editing its body.
- Add further comments in editing mode using the same cursor or visual-range
  commands. Range endpoints must be source lines; intervening review blocks
  are excluded from the anchor. Pending source and comment edits are retained.
- Delete a complete comment block in editing mode, including its header,
  footer, replies, and paired delimiters when present, then `:w` to delete that
  thread from the sidecar. Partial boundary deletion is rejected. Deleting the
  final thread leaves an empty review file.
- Use `:w` to write the source and sidecar together.
- Use `:BetwixtVirtual` to return to virtual display.
- Use `:BetwixtVirtual!` to discard unsaved materialized changes.

Materialization uses the current filetype's `commentstring`. Prefix-only forms,
such as Lua's `-- %s`, prefix every review line. Paired forms put their opening
and closing tokens on separate protected lines outside the aligned Betwixt
frame, leaving the header, body, replies, and footer prefix-free. This keeps the
temporary source buffer parseable while the write hook keeps the complete
review section out of the source file. During `:w`, Betwixt temporarily
presents pure source to Neovim's native write path, so normal `BufWritePre`
formatting and `BufWritePost` hooks run without seeing review lines. It then
restores the interleaved view. The sidecar is written only after the native
source write succeeds, so a rejected source write leaves the sidecar untouched
and the pending buffer editable.

### Deleting a comment

1. Press `<leader>re` to enter interleaved editing if needed.
2. Place the cursor on the thread header, press `V`, select through its footer,
   and press `d`. For paired syntax such as Markdown, select from `<!--` through
   `-->`, including both delimiter lines and any replies.
3. Run `:w` to remove the thread from the sidecar and save any source edits.

Clearing only the body leaves an empty comment. Deleting just a boundary is
rejected on write. Before writing, `:BetwixtVirtual!` cancels the deletion along
with all other unsaved interleaved edits. Deleting the last thread leaves an
empty sidecar that can be attached again.

### Human-agent handoff

The sidecar, rather than the materialized source buffer, is the shared review
conversation. Before handing a review to an external agent:

1. Use `:w` to persist source and review edits separately.
2. Run `:BetwixtVirtual` so Neovim is no longer holding an interleaved edit.
3. Let the agent read the clean source and edit the `.betwixt.md` sidecar
   directly. The included
   [Betwixt comment skill](.agents/skills/betwixt-comment/SKILL.md) supports
   appending either a root comment or a linear `### Reply`.
4. Run `:BetwixtRefresh` to display the updated sidecar.

There is no standalone agent-facing `reply` command or CLI yet. The Lua
`require("betwixt").reply(buffer)` function backs the interactive
`:BetwixtReply` flow and selects the nearest projected comment; it is not a
filesystem mutation API. If an external edit arrives while the buffer remains
interleaved, Betwixt rejects the next write rather than overwrite the changed
sidecar.

### CodeDiff review

For the tested single-file CodeDiff path:

1. Open the saved working-tree file in its normal buffer.
2. Create the first comment with `:BetwixtComment`, or reopen an existing
   review with `:BetwixtAttach`.
3. Return to virtual mode and run `:CodeDiff file HEAD~1` to compare the
   working file with the previous commit. Replace `HEAD~1` with the desired
   revision.
4. Use the ordinary Betwixt commands in CodeDiff's editable working-file pane.
   `:w` writes the working file and sidecar; `:BetwixtVirtual` restores the
   virtual thread display.

In side-by-side mode, Betwixt adds an equal-height highlighted spacer on the
opposite side when the anchor resolves uniquely in both versions. CodeDiff's
`t` mapping can switch between side-by-side and inline layouts. Stale or
ambiguous anchors do not receive a speculative opposite spacer.

### Filetype support

Materialized editing requires a usable `commentstring`. Current automated
coverage is:

| Filetype | Neovim `commentstring` | Tested coverage |
| --- | --- | --- |
| Lua | `-- %s` | Full comment, reply, anchoring, write, CodeDiff, and Diffview flows |
| JavaScript | `// %s` | Materialized comment editing and source/sidecar separation |
| Python | `# %s` | Lazy first-comment creation and materialized editing |
| Markdown | `<!-- %s -->` | Comment and reply creation, prefix-free materialized editing, delimiter safety, and separated writes |

In Markdown, a materialized thread looks like this:

```markdown
<!--
╭─ betwixt · reviewer · open · comment · ../notes.md:3-3
Could this be more direct?
╰─ betwixt
-->
```

The HTML-comment delimiters live on their own protected boundary lines. Review
text containing `<!--` or `-->` is rejected rather than silently escaped.
CommonMark treats an HTML comment inside a fenced code block as literal code,
so a thread materialized there may appear in a live Markdown preview even
though Betwixt still removes it from the source on write. Automated Markdown
coverage currently targets ordinary prose; lists, block quotes, fenced code,
and editor-specific preview behavior remain useful live-trial cases.

Run `:help betwixt` for the command reference.

## Status

This is an early plugin slice, tested with Neovim 0.12. The retained fixtures
cover lazy first-comment creation, native write hooks and failure recovery, Lua,
JavaScript, Python, and Markdown comment syntax, ordinary attachment,
simultaneous source and sidecar writes, linear reply creation and editing,
resolved-thread highlighting, context-assisted anchoring under common source
edits, CodeDiff alignment, and Diffview editing.

Multi-file artifact organization, automatic anchor migration, nested reply
trees, automatic resolution, and hosted collaboration remain deliberately
outside the current slice.

Active feature development is paused while this slice receives a controlled
local pilot. It expects saved normal file buffers and a filetype with a usable
`commentstring`. Reopen an existing review with `:BetwixtAttach` or `:BetwixtReload`;
there is no automatic sidecar discovery on buffer open.
CodeDiff is the better-tested live review path. Diffview works when Betwixt is
attached to its editable working pane, but that attachment is also manual.

## Development

The focused checks are standalone Neovim scripts under `tests/`. The richer
interactive launchers and their known diff-view limitations are documented in
`experiment/README.md`. Headless viewer tests exercise actual CodeDiff and
Diffview buffers, windows, virtual rows, materialized review lines, writes, and
screen-row alignment. Terminal color rendering, flicker, and subjective
interaction still require an interactive check.

## License

Betwixt is available under the MIT License. See `LICENSE`.
