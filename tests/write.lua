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
betwixt.interleave(source_buffer)

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

local function assert_pure_source(stage)
  assert(table.concat(buffer_lines(), "\n"):find("betwixt", 1, true) == nil, stage .. " must see pure source")
end

local pre_count = 0
local post_count = 0
local write_group = vim.api.nvim_create_augroup("BetwixtNativeWriteTest", { clear = true })
vim.api.nvim_create_autocmd("BufWritePre", {
  buffer = source_buffer,
  group = write_group,
  callback = function()
    pre_count = pre_count + 1
    assert_pure_source("BufWritePre")
    local lines = buffer_lines()
    for index, line in ipairs(lines) do
      if line == "  local subtotal=value" then
        vim.api.nvim_buf_set_lines(source_buffer, index - 1, index, false, { "  local subtotal = value" })
      end
    end
  end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  buffer = source_buffer,
  group = write_group,
  callback = function()
    post_count = post_count + 1
    assert_pure_source("BufWritePost")
  end,
})

local body_row = find_line("-- Could this be clearer?")
local source_row = find_line("  local subtotal = value")
vim.api.nvim_buf_set_lines(source_buffer, body_row - 1, body_row, false, { "-- Edited review note." })
vim.api.nvim_buf_set_lines(source_buffer, source_row - 1, source_row, false, { "  local subtotal=value" })
vim.cmd("write")

assert(pre_count == 1, "materialized write should trigger BufWritePre exactly once")
assert(post_count == 1, "materialized write should trigger BufWritePost exactly once")
assert(vim.deep_equal(vim.fn.readfile(source_path), source), "BufWritePre formatting should reach the source file")
assert(
  table.concat(vim.fn.readfile(sidecar_path), "\n"):find("Edited review note%.") ~= nil,
  "the same write should persist the review edit"
)
assert(find_line("  local subtotal = value") > 0, "the rematerialized buffer should contain formatted source")
assert(find_line("-- Edited review note.") > 0, "the rematerialized buffer should retain the review edit")
assert(not vim.bo[source_buffer].modified, "a successful combined write should clear modified state")

vim.cmd("silent undo")
assert(find_line("  local subtotal = value") > 0, "undo after write must retain a pure source line")
assert(find_line("-- Could this be clearer?") > 0, "undo after write should restore the previous review text")
assert(
  table.concat(buffer_lines(), "\n"):find("╭─ betwixt", 1, true) ~= nil,
  "undo must not expose the temporary pure-source view"
)
assert(vim.bo[source_buffer].modified, "undo after write should restore modified state")
vim.cmd("silent redo")
assert(find_line("  local subtotal = value") > 0, "redo should restore formatter output")
assert(find_line("-- Edited review note.") > 0, "redo should restore the written review edit")

local failed_body_row = find_line("-- Edited review note.")
vim.api.nvim_buf_set_lines(source_buffer, failed_body_row - 1, failed_body_row, false, { "-- Pending failed write." })
local sidecar_before_failure = vim.fn.readfile(sidecar_path)
local source_before_failure = vim.fn.readfile(source_path)
vim.api.nvim_create_autocmd("BufWritePre", {
  buffer = source_buffer,
  group = write_group,
  once = true,
  callback = function()
    error("intentional write failure")
  end,
})
local failed_ok = pcall(function()
  vim.cmd("write")
end)
assert(not failed_ok, "a native BufWritePre failure should reject the combined write")
assert(vim.deep_equal(vim.fn.readfile(source_path), source_before_failure), "failed write must preserve source on disk")
assert(
  vim.deep_equal(vim.fn.readfile(sidecar_path), sidecar_before_failure),
  "failed native write must leave the sidecar untouched"
)
assert(find_line("-- Pending failed write.") > 0, "failed write must restore the pending interleaved buffer")
assert(vim.bo[source_buffer].modified, "failed write should leave pending edits modified")

betwixt.virtualize(source_buffer, true)
betwixt.detach(source_buffer, false)
vim.api.nvim_del_augroup_by_id(write_group)
vim.fn.delete(temporary, "rf")
print("betwixt native write pipeline: ok")
