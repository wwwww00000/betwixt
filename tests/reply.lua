vim.cmd("runtime plugin/betwixt.lua")
local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
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
  "",
  "### Reply",
  "",
  "author: agent",
  "body:",
  "The intermediate name could describe the unit.",
}

assert(vim.fn.writefile(source, source_path) == 0)
assert(vim.fn.writefile(sidecar, sidecar_path) == 0)
vim.cmd.edit(vim.fn.fnameescape(source_path))
local source_buffer = vim.api.nvim_get_current_buf()
betwixt.attach(sidecar_path)

local virtual_namespace = vim.api.nvim_get_namespaces()["betwixt-virtual"]
local interleaved_namespace = vim.api.nvim_get_namespaces()["betwixt-interleaved"]

local function marks(namespace)
  return vim.api.nvim_buf_get_extmarks(source_buffer, namespace, 0, -1, { details = true })
end

local function virtual_lines()
  local projected = marks(virtual_namespace)
  assert(#projected == 1, "the thread should use one anchored virtual block")
  return projected[1][4].virt_lines
end

local function visible_text(lines)
  local result = {}
  for _, line in ipairs(lines) do
    table.insert(result, line[1][1])
  end
  return table.concat(result, "\n")
end

local function buffer_lines()
  return vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
end

local function find_line(expected)
  for index, line in ipairs(buffer_lines()) do
    if line == expected then
      return index
    end
  end
  error("missing line: " .. expected .. "\n" .. table.concat(buffer_lines(), "\n"))
end

local projected = virtual_lines()
assert(#projected == 5, "a root body, one reply, and the frame should occupy five virtual rows")
assert(visible_text(projected):find("├─ reply · agent", 1, true), "a stored reply should render under its root")
for _, line in ipairs(projected) do
  assert(line[1][2] == "BetwixtComment", "an open thread should use the amber highlight")
end

local resolved_highlight = vim.api.nvim_get_hl(0, { name = "BetwixtResolvedComment", link = false })
local expected_resolved_background = tonumber(vim.o.background == "light" and "E2E2E2" or "303030", 16)
assert(resolved_highlight.bg == expected_resolved_background, "resolved comments should define a gray background")
assert(vim.fn.exists(":BetwixtReply") == 2, "an attached buffer should expose :BetwixtReply")

local before_cancel = vim.fn.readfile(sidecar_path)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("BetwixtReply")
assert(find_line("-- ├─ reply · reviewer") > 0, "reply creation should materialize an attributed separator")
betwixt.virtualize(source_buffer, true)
assert(vim.deep_equal(vim.fn.readfile(sidecar_path), before_cancel), "canceling a reply must not change the sidecar")
assert(
  not visible_text(virtual_lines()):find("reply · reviewer", 1, true),
  "canceling should remove the pending reply"
)

vim.cmd("BetwixtReply")
local header_row = find_line("-- ╭─ betwixt · human · open · question · sample.lua:2-3")
local root_body_row = find_line("-- Could this be clearer?")
local existing_reply_row = find_line("-- The intermediate name could describe the unit.")
local new_reply_header_row = find_line("-- ├─ reply · reviewer")
assert(
  vim.api.nvim_win_get_cursor(0)[1] == new_reply_header_row + 1,
  "reply creation should place the cursor in the new blank body"
)
vim.api.nvim_buf_set_lines(
  source_buffer,
  header_row - 1,
  header_row,
  false,
  { "-- ╭─ betwixt · human · resolved · question · sample.lua:2-3" }
)
vim.api.nvim_buf_set_lines(source_buffer, root_body_row - 1, root_body_row, false, { "-- The root was clarified." })
vim.api.nvim_buf_set_lines(
  source_buffer,
  existing_reply_row - 1,
  existing_reply_row,
  false,
  { "-- The unit is now documented." }
)
vim.api.nvim_buf_set_lines(
  source_buffer,
  new_reply_header_row - 1,
  new_reply_header_row + 1,
  false,
  { "-- ├─ reply · teammate", "-- Looks good to me." }
)
vim.api.nvim_buf_set_lines(source_buffer, 0, 0, false, { "-- source edit made during review" })
vim.cmd("write")

local written_sidecar = table.concat(vim.fn.readfile(sidecar_path), "\n")
assert(written_sidecar:find("status: resolved", 1, true), "root status edits should persist")
assert(written_sidecar:find("The root was clarified.", 1, true), "root body edits should persist")
assert(written_sidecar:find("author: agent\nbody:\nThe unit is now documented."), "stored reply edits should persist")
assert(written_sidecar:find("author: teammate\nbody:\nLooks good to me."), "new reply author and body should persist")
local expected_source = { "-- source edit made during review" }
vim.list_extend(expected_source, source)
assert(vim.deep_equal(vim.fn.readfile(source_path), expected_source), "the same write should persist only source lines")

local materialized_marks = marks(interleaved_namespace)
assert(#materialized_marks == 1, "the materialized thread should retain one frame")
assert(
  materialized_marks[1][4].hl_group == "BetwixtResolvedComment",
  "a written resolved status should mute the materialized thread"
)

betwixt.virtualize(source_buffer, false)
projected = virtual_lines()
assert(#projected == 7, "two replies should increase the virtual block height")
assert(visible_text(projected):find("Looks good to me.", 1, true), "the new reply should appear in virtual mode")
for _, line in ipairs(projected) do
  assert(line[1][2] == "BetwixtResolvedComment", "a resolved thread should use the gray highlight")
end

betwixt.interleave(source_buffer)
local damaged_reply_row = find_line("-- ├─ reply · agent")
vim.api.nvim_buf_set_lines(source_buffer, damaged_reply_row - 1, damaged_reply_row, false, { "-- damaged reply" })
local damaged_ok = pcall(function()
  vim.cmd("write")
end)
assert(not damaged_ok, "damaging a reply separator should reject the complete write")
assert(written_sidecar == table.concat(vim.fn.readfile(sidecar_path), "\n"), "a rejected write must preserve replies")

betwixt.virtualize(source_buffer, true)
betwixt.detach(source_buffer, false)
vim.api.nvim_buf_delete(source_buffer, { force = true })
vim.fn.delete(temporary, "rf")
print("betwixt replies and resolved comments: ok")
