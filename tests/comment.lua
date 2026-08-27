local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
vim.g.mapleader = " "
betwixt.setup({ author = "reviewer" })
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

local function buffer_lines()
  return vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
end

local function find_line(expected)
  for index, line in ipairs(buffer_lines()) do
    if line == expected then
      return index
    end
  end
  error("missing line: " .. expected)
end

local function replace_line(line, value)
  vim.api.nvim_buf_set_lines(source_buffer, line - 1, line, false, { value })
end

local function sidecar_text()
  return table.concat(vim.fn.readfile(sidecar_path), "\n")
end

local function count_comments(text)
  local count = 0
  for _ in text:gmatch("## Comment") do
    count = count + 1
  end
  return count
end

local function has_buffer_mapping(mode, lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(source_buffer, mode)) do
    if mapping.lhs == lhs then
      return true
    end
  end
  return false
end

assert(has_buffer_mapping("n", " rc"), "normal <leader>rc should create a current-line comment")
assert(has_buffer_mapping("x", " rc"), "visual <leader>rc should create a selected-range comment")

vim.cmd("1,2BetwixtComment question")
assert(vim.bo[source_buffer].modified, "an unwritten new comment should keep the buffer modified")
local visual_header = find_line("-- ╭─ betwixt · reviewer · open · question · sample.lua:1-2")
assert(buffer_lines()[visual_header + 1] == "-- ", "a new range comment should start with an empty editable body")
assert(buffer_lines()[visual_header + 2] == "-- ╰─ betwixt", "a new range comment should have a protected footer")
assert(vim.api.nvim_win_get_cursor(0)[1] == visual_header + 1, "creation should target the new comment body")
replace_line(visual_header, "-- ╭─ betwixt · reviewer · open · risk · sample.lua:1-2")
replace_line(visual_header + 1, "-- This covers the selected range.")
vim.api.nvim_buf_call(source_buffer, function()
  vim.cmd("write")
end)
assert(vim.deep_equal(vim.fn.readfile(source_path), source), "writing a range comment must not change source")
local written = sidecar_text()
assert(written:find("range: 1%-2\nauthor: reviewer\nstatus: open\ntype: risk"), "edited header metadata should persist")
assert(
  written:find("anchor:\n    local function total%(value%)\n      local subtotal = value\nbody:"),
  "the selected source lines should become the exact anchor"
)
assert(written:find("This covers the selected range%.", 1, false), "the range comment body should persist")
betwixt.virtualize(source_buffer, false)

local edited_source = vim.deepcopy(source)
edited_source[4] = "end -- retained source edit"
replace_line(4, edited_source[4])
assert(vim.bo[source_buffer].modified, "the current-line flow should accept an ordinary pending source edit")
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("BetwixtComment")
local cursor_header = find_line("-- ╭─ betwixt · reviewer · open · comment · sample.lua:4-4")
replace_line(cursor_header + 1, "-- This was noted at the cursor.")
vim.api.nvim_buf_call(source_buffer, function()
  vim.cmd("write")
end)
assert(vim.deep_equal(vim.fn.readfile(source_path), edited_source), "one write should persist the pending source edit")
written = sidecar_text()
assert(count_comments(written) == 3, "the sidecar should contain both newly created comments")
assert(
  written:find("range: 4%-4\nauthor: reviewer\nstatus: open\ntype: comment"),
  "current-line defaults should persist"
)
assert(
  written:find("anchor:\n    end %-%- retained source edit\nbody:\nThis was noted at the cursor%."),
  "the current edited line should become the anchor"
)
betwixt.virtualize(source_buffer, false)

local before_cancel = vim.fn.readfile(sidecar_path)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("BetwixtComment risk")
betwixt.virtualize(source_buffer, true)
assert(
  vim.deep_equal(vim.fn.readfile(sidecar_path), before_cancel),
  "discarding creation must leave the sidecar unchanged"
)
assert(vim.deep_equal(buffer_lines(), edited_source), "discarding creation should restore the ordinary source buffer")

betwixt.detach(source_buffer, true)
vim.fn.delete(temporary, "rf")
print("betwixt comment creation: ok")
