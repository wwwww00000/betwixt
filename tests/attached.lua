local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
vim.cmd("filetype plugin on")

local source_path = vim.fs.joinpath(temporary, "sample.lua")
local sidecar_path = vim.fs.joinpath(temporary, "review.betwixt.md")
local source = {
  "local function total(value)",
  "  local subtotal = value",
  "  return subtotal",
  "end",
}
local sidecar = {
  "# Betwixt review",
  "",
  "file: sample.lua",
  "",
  "## Comment",
  "",
  "range: 2-3",
  "author: human",
  "status: open",
  "type: question",
  "anchor:",
  "      local subtotal = value",
  "      return subtotal",
  "body:",
  "Could this be clearer?",
}

assert(vim.fn.writefile(source, source_path) == 0)
assert(vim.fn.writefile(sidecar, sidecar_path) == 0)
vim.cmd.edit(vim.fn.fnameescape(source_path))

local source_buffer = vim.api.nvim_get_current_buf()
betwixt.attach(sidecar_path)
local comment_highlight = vim.api.nvim_get_hl(0, { name = "BetwixtComment", link = false })
local expected_background = tonumber(vim.o.background == "light" and "F3DFB3" or "4A3418", 16)
assert(comment_highlight.bg == expected_background, "comments should use the amber background")
assert(vim.bo[source_buffer].buftype == "", "attachment should preserve the normal source buffer")
assert(vim.bo[source_buffer].modifiable, "attached source should remain editable")
assert(
  vim.deep_equal(vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false), source),
  "virtual comments must not alter source lines"
)

local function virtual_text(buffer)
  local text = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, -1, 0, -1, { details = true })) do
    for _, virtual_line in ipairs(mark[4].virt_lines or {}) do
      local segments = {}
      for _, segment in ipairs(virtual_line) do
        table.insert(segments, segment[1])
      end
      table.insert(text, table.concat(segments))
    end
  end
  return table.concat(text, "\n")
end

local function find_line(lines, pattern)
  for index, line in ipairs(lines) do
    if line:match(pattern) then
      return index
    end
  end
  error("missing line matching " .. pattern)
end

assert(virtual_text(source_buffer):find("Could this be clearer%?") ~= nil, "comment body should be projected")

vim.api.nvim_win_set_cursor(0, { 2, 0 })
assert(betwixt.interleave(source_buffer) == source_buffer, "editing should stay in the source buffer")
assert(vim.api.nvim_get_current_buf() == source_buffer, "interleaving should not switch buffers")
local interleaved = vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
local header_row = find_line(interleaved, "^%-%- ╭─ betwixt")
local body_row = find_line(interleaved, "^%-%- Could this be clearer%?$")
assert(header_row > 2, "the physical comment should follow its target range")
assert(interleaved[body_row + 1] == "-- ╰─ betwixt", "the whole frame should use Lua comment syntax")

vim.api.nvim_buf_set_lines(source_buffer, body_row - 1, body_row, false, { "-- Edited in the source buffer." })
vim.cmd("silent undo")
assert(
  vim.api.nvim_buf_get_lines(source_buffer, body_row - 1, body_row, false)[1] == "-- Could this be clearer?",
  "an interleaved comment edit should have ordinary undo"
)
vim.cmd("silent redo")
vim.api.nvim_buf_set_lines(source_buffer, 0, 0, false, { "-- inserted with comments interleaved" })
vim.cmd("write")
assert(
  table.concat(vim.fn.readfile(sidecar_path), "\n"):find("Edited in the source buffer%.") ~= nil,
  "the same-buffer write should persist the sidecar"
)
local interleaved_source = { "-- inserted with comments interleaved" }
vim.list_extend(interleaved_source, source)
assert(
  vim.deep_equal(vim.fn.readfile(source_path), interleaved_source),
  "the same write should persist source edits without Betwixt lines"
)
assert(
  table.concat(vim.fn.readfile(source_path), "\n"):find("betwixt") == nil,
  "syntactic Betwixt comments must never reach the source file"
)

betwixt.virtualize(source_buffer, false)
assert(
  vim.deep_equal(vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false), interleaved_source),
  "virtual mode should restore a pure source buffer"
)
assert(virtual_text(source_buffer):find("Edited in the source buffer%.") ~= nil, "virtual display should show the edit")

vim.api.nvim_buf_set_lines(source_buffer, 0, 0, false, { "-- inserted in the real source buffer" })
vim.cmd("write")
local shifted_source = { "-- inserted in the real source buffer" }
vim.list_extend(shifted_source, interleaved_source)
assert(vim.deep_equal(vim.fn.readfile(source_path), shifted_source), "normal source write should remain native")
assert(virtual_text(source_buffer):find("moved to 4%-5") ~= nil, "source write should refresh moved anchors")

vim.api.nvim_win_set_cursor(0, { 4, 0 })
betwixt.interleave(source_buffer)
interleaved = vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
header_row = find_line(interleaved, "^%-%- ╭─ betwixt")
body_row = find_line(interleaved, "^%-%- Edited in the source buffer%.$")
vim.api.nvim_buf_set_lines(source_buffer, header_row - 1, header_row, false, { "-- damaged frame" })
local damaged_write_ok = pcall(function()
  vim.cmd("write")
end)
assert(not damaged_write_ok, "a damaged interleaved frame must reject the entire write")
assert(vim.deep_equal(vim.fn.readfile(source_path), shifted_source), "a damaged frame must not change source")
vim.cmd("silent undo")
vim.api.nvim_buf_set_lines(source_buffer, body_row - 1, body_row, false, { "-- Unsaved interleaved edit." })
local external_sidecar = vim.fn.readfile(sidecar_path)
for index, line in ipairs(external_sidecar) do
  if line == "Edited in the source buffer." then
    external_sidecar[index] = "External sidecar edit."
  end
end
assert(vim.fn.writefile(external_sidecar, sidecar_path) == 0)
local conflicting_write_ok = pcall(function()
  vim.cmd("write")
end)
assert(not conflicting_write_ok, "interleaved write must not overwrite an externally changed sidecar")
assert(
  table.concat(vim.fn.readfile(sidecar_path), "\n"):find("External sidecar edit%.") ~= nil,
  "the rejected write should preserve the external sidecar edit"
)

betwixt.virtualize(source_buffer, true)
betwixt.detach(source_buffer, false)
assert(virtual_text(source_buffer) == "", "detach should remove virtual comments")
vim.api.nvim_buf_delete(source_buffer, { force = true })
vim.fn.delete(temporary, "rf")

print("betwixt attached experiment: ok")
