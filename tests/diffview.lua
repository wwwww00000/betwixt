local root = vim.fn.getcwd()
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
vim.cmd("filetype plugin on")

local function run(command)
  local result = vim.system(command, { cwd = temporary, text = true }):wait()
  assert(result.code == 0, table.concat(command, " ") .. ": " .. (result.stderr or ""))
end

local source_path = vim.fs.joinpath(temporary, "sample.lua")
local sidecar_path = vim.fs.joinpath(temporary, "review.betwixt.md")
local committed_source = {
  "local function total(value)",
  "  local subtotal = value",
  "  return subtotal",
  "end",
}
local working_source = vim.deepcopy(committed_source)
working_source[1] = "local function changed(value)"
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

assert(vim.fn.writefile(committed_source, source_path) == 0)
assert(vim.fn.writefile(sidecar, sidecar_path) == 0)
run({ "git", "init", "-q" })
run({ "git", "add", "sample.lua", "review.betwixt.md" })
run({ "git", "-c", "user.name=Betwixt", "-c", "user.email=betwixt@example.invalid", "commit", "-qm", "fixture" })
assert(vim.fn.writefile(working_source, source_path) == 0)

if not vim.g.diffview_nvim_loaded then
  vim.cmd("runtime plugin/diffview.lua")
end

local betwixt = require("betwixt")
local attached_buffer
require("diffview").setup({
  use_icons = false,
  hooks = {
    diff_buf_read = function(buffer)
      local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buffer))
      if name == vim.fs.normalize(source_path) then
        betwixt.attach(sidecar_path, { buffer = buffer })
        attached_buffer = buffer
      end
    end,
  },
})

vim.cmd.cd(temporary)
vim.cmd("DiffviewOpen HEAD -- sample.lua")
assert(
  vim.wait(5000, function()
    return attached_buffer ~= nil
  end, 20),
  "Diffview did not expose the working-tree buffer"
)
assert(vim.bo[attached_buffer].buftype == "", "Diffview working side should be the normal source buffer")
assert(vim.bo[attached_buffer].modifiable, "Diffview working side should remain editable")

local virtual_comment = false
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(attached_buffer, -1, 0, -1, { details = true })) do
  if mark[4].virt_lines then
    virtual_comment = true
  end
end
assert(virtual_comment, "Betwixt should project a comment inside the Diffview working buffer")

local source_win = vim.fn.win_findbuf(attached_buffer)[1]
assert(source_win and source_win ~= 0, "Diffview working buffer should be visible")
vim.api.nvim_win_set_cursor(source_win, { 2, 0 })
betwixt.interleave(attached_buffer)
local interleaved = vim.api.nvim_buf_get_lines(attached_buffer, 0, -1, false)
local body_row
for index, line in ipairs(interleaved) do
  if line == "-- Could this be clearer?" then
    body_row = index
    break
  end
end
assert(body_row, "Diffview should contain the syntactically commented interleaved body")
vim.api.nvim_buf_set_lines(attached_buffer, body_row - 1, body_row, false, { "-- Edited from inside Diffview." })
vim.api.nvim_buf_call(attached_buffer, function()
  vim.cmd("write")
end)
assert(
  table.concat(vim.fn.readfile(sidecar_path), "\n"):find("Edited from inside Diffview%.") ~= nil,
  "Diffview same-buffer edit should persist the sidecar"
)
assert(
  vim.deep_equal(vim.fn.readfile(source_path), working_source),
  "syntactic Betwixt comment lines inside Diffview must not reach source"
)
betwixt.virtualize(attached_buffer, false)
assert(
  vim.deep_equal(vim.api.nvim_buf_get_lines(attached_buffer, 0, -1, false), working_source),
  "Diffview should retain its real working buffer after returning to virtual mode"
)

betwixt.detach(attached_buffer, true)
vim.cmd("DiffviewClose")
vim.cmd.cd(root)
vim.fn.delete(temporary, "rf")

print("betwixt Diffview integration: ok")
