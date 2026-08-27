local root = vim.fn.getcwd()
local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")

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

local function buffer_lines(buffer)
  return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

local function find_line(lines, pattern)
  for index, line in ipairs(lines) do
    if line:match(pattern) then
      return index
    end
  end
  error("missing line matching " .. pattern)
end

local after_buffer = betwixt.open(sidecar_path)
local lines = buffer_lines(after_buffer)
local target_row = find_line(lines, "^  return subtotal$")
local header_row = find_line(lines, "^╭─ betwixt")
assert(header_row > target_row, "default comment placement should follow the range")

local body_row = find_line(lines, "^Could this be clearer%?$")
vim.api.nvim_buf_set_lines(
  after_buffer,
  header_row - 1,
  header_row,
  false,
  { "╭─ betwixt · human · open · risk · sample.lua:2-3" }
)
vim.api.nvim_buf_set_lines(after_buffer, body_row - 1, body_row, false, { "This edit came from the composite buffer." })
vim.api.nvim_buf_call(after_buffer, function()
  vim.cmd("silent undo")
end)
assert(
  buffer_lines(after_buffer)[body_row] == "Could this be clearer?",
  "ordinary buffer undo should restore a comment edit"
)
vim.api.nvim_buf_call(after_buffer, function()
  vim.cmd("silent redo")
end)
assert(
  buffer_lines(after_buffer)[body_row] == "This edit came from the composite buffer.",
  "ordinary buffer redo should restore a comment edit"
)
vim.api.nvim_buf_call(after_buffer, function()
  vim.cmd("write")
end)
assert(
  table.concat(vim.fn.readfile(sidecar_path), "\n"):find("This edit came from the composite buffer%.") ~= nil,
  "write should persist the comment body"
)
assert(
  table.concat(vim.fn.readfile(sidecar_path), "\n"):find("type: risk") ~= nil,
  "write should persist editable header metadata"
)
assert(vim.deep_equal(vim.fn.readfile(source_path), source), "writing a comment must not change source")

local saved_sidecar = vim.fn.readfile(sidecar_path)
lines = buffer_lines(after_buffer)
body_row = find_line(lines, "^This edit came from the composite buffer%.$")
vim.api.nvim_buf_set_lines(after_buffer, body_row - 1, body_row, false, { "Unsaved local comment edit." })
local external_sidecar = vim.deepcopy(saved_sidecar)
for index, line in ipairs(external_sidecar) do
  if line == "This edit came from the composite buffer." then
    external_sidecar[index] = "External sidecar edit."
  end
end
assert(vim.fn.writefile(external_sidecar, sidecar_path) == 0)
local conflicting_write_ok = pcall(function()
  vim.api.nvim_buf_call(after_buffer, function()
    vim.cmd("write")
  end)
end)
assert(not conflicting_write_ok, "a write should not overwrite an externally changed sidecar")
assert(
  table.concat(vim.fn.readfile(sidecar_path), "\n"):find("External sidecar edit%.") ~= nil,
  "the external sidecar edit should survive the rejected write"
)
assert(vim.fn.writefile(saved_sidecar, sidecar_path) == 0)
vim.api.nvim_buf_call(after_buffer, function()
  vim.cmd("BetwixtReload!")
end)

lines = buffer_lines(after_buffer)
local source_row = find_line(lines, "^local function total")
vim.api.nvim_buf_set_lines(after_buffer, source_row - 1, source_row, false, { "local function changed(value)" })
vim.api.nvim_buf_set_lines(after_buffer, source_row, source_row, false, { "-- inserted through the composite buffer" })
lines = buffer_lines(after_buffer)
body_row = find_line(lines, "^This edit came from the composite buffer%.$")
vim.api.nvim_buf_set_lines(after_buffer, body_row - 1, body_row, false, { "Source and comment changed together." })
vim.api.nvim_buf_call(after_buffer, function()
  vim.cmd("write")
end)
local written_source = vim.deepcopy(source)
written_source[1] = "local function changed(value)"
table.insert(written_source, 2, "-- inserted through the composite buffer")
assert(vim.deep_equal(vim.fn.readfile(source_path), written_source), "write should persist projected source edits")
assert(
  table.concat(vim.fn.readfile(sidecar_path), "\n"):find("Source and comment changed together%.") ~= nil,
  "the same write should persist comment edits"
)

local shifted_source = {
  "-- inserted above the anchor",
  "",
}
vim.list_extend(shifted_source, written_source)
assert(vim.fn.writefile(shifted_source, source_path) == 0)
vim.api.nvim_buf_call(after_buffer, function()
  vim.cmd("BetwixtReload!")
end)
lines = buffer_lines(after_buffer)
header_row = find_line(lines, "^╭─ betwixt")
assert(
  lines[header_row]:find("moved to 5%-6") ~= nil,
  "a unique shifted anchor should be shown as moved: " .. lines[header_row]
)

local stale_source = vim.deepcopy(shifted_source)
stale_source[5] = "  local amount = value"
assert(vim.fn.writefile(stale_source, source_path) == 0)
vim.api.nvim_buf_call(after_buffer, function()
  vim.cmd("BetwixtReload")
end)
lines = buffer_lines(after_buffer)
header_row = find_line(lines, "^╭─ betwixt")
assert(lines[header_row]:find("stale") ~= nil, "a missing anchor should be shown as stale")

assert(vim.fn.writefile(shifted_source, source_path) == 0)
vim.api.nvim_buf_call(after_buffer, function()
  vim.cmd("BetwixtReload")
end)

local before_buffer = betwixt.open(sidecar_path, { placement = "before" })
lines = buffer_lines(before_buffer)
target_row = find_line(lines, "^  local subtotal = value$")
header_row = find_line(lines, "^╭─ betwixt")
assert(header_row < target_row, "bang placement should put the comment before the range")

local fixture_buffer = betwixt.open(vim.fs.joinpath(root, "experiment", "review.betwixt.md"))
local fixture_headers = 0
for _, line in ipairs(buffer_lines(fixture_buffer)) do
  if line:match("^╭─ betwixt") then
    fixture_headers = fixture_headers + 1
    assert(not line:find("stale"), "fixture anchors should initially be current")
    assert(not line:find("ambiguous"), "fixture anchors should initially be unambiguous")
  end
end
assert(fixture_headers == 2, "fixture should project the human and agent comments")

if vim.api.nvim_buf_is_valid(after_buffer) then
  vim.api.nvim_buf_delete(after_buffer, { force = true })
end
if vim.api.nvim_buf_is_valid(before_buffer) then
  vim.api.nvim_buf_delete(before_buffer, { force = true })
end
if vim.api.nvim_buf_is_valid(fixture_buffer) then
  vim.api.nvim_buf_delete(fixture_buffer, { force = true })
end
vim.fn.delete(temporary, "rf")

print("betwixt experiment: ok (" .. root .. ")")
