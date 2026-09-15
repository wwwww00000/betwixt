vim.cmd("runtime plugin/betwixt.lua")
local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary .. "/src", "p")
vim.fn.mkdir(temporary .. "/.git", "p")
vim.cmd.cd(vim.fn.fnameescape(temporary .. "/src"))
vim.cmd("filetype plugin on")
local path = temporary .. "/src/sample.lua"
local sidecar = temporary .. "/.betwixt/src/sample.lua.betwixt.md"
local source = { "local a = 1", "local b = 2", "return a + b" }
vim.fn.writefile(source, path)
vim.cmd.edit(path)
local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end
local function find(text)
  for index, line in ipairs(lines()) do
    if line == text then
      return index
    end
  end
  error("missing " .. text)
end
local function body(text)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { "-- " .. text })
end
vim.cmd("BetwixtReload") -- no sidecar is a no-op
vim.cmd("1BetwixtComment")
body("first pending")
local row = find("local b = 2")
vim.api.nvim_buf_set_lines(0, row - 1, row, false, { "local b = 3" })
vim.cmd(row .. "," .. find("return a + b") .. "BetwixtComment risk")
body("second pending")
assert(not vim.uv.fs_stat(temporary .. "/.betwixt"))
vim.cmd.write()
local text = table.concat(vim.fn.readfile(sidecar), "\n")
assert(text:find("first pending", 1, true) and text:find("second pending", 1, true))
assert(text:find("range: 2-3", 1, true))
assert(text:find("file: ../../src/sample.lua", 1, true))
assert(vim.fn.readfile(path)[2] == "local b = 3")
-- Reject targeting a review block without losing edits.
assert(not pcall(vim.cmd, find("-- first pending") .. "BetwixtComment"))
-- Delete a complete thread, then add another before syncing.
local first = find("-- first pending")
vim.api.nvim_buf_set_lines(0, first - 2, first + 1, false, {})
vim.cmd(find("local a = 1") .. "BetwixtComment")
body("replacement")
vim.cmd.write()
text = table.concat(vim.fn.readfile(sidecar), "\n")
assert(not text:find("first pending", 1, true))
assert(text:find("second pending", 1, true) and text:find("replacement", 1, true))
-- Cancelling several additions restores the last saved review.
betwixt.virtualize(nil, false)
local saved = vim.fn.readfile(sidecar)
vim.cmd("1BetwixtComment")
body("cancel one")
vim.cmd(find("local b = 3") .. "BetwixtComment")
body("cancel two")
assert(not pcall(vim.cmd, "BetwixtReload"))
vim.cmd("BetwixtReload!")
assert(vim.deep_equal(vim.fn.readfile(sidecar), saved))
assert(vim.deep_equal(lines(), vim.fn.readfile(path)))
vim.cmd("BetwixtEdit")
-- Reject a partial boundary deletion and keep both files untouched.
local footer = find("-- ╰─ betwixt")
vim.api.nvim_buf_set_lines(0, footer - 1, footer, false, {})
assert(not pcall(vim.cmd, "write"))
assert(vim.deep_equal(vim.fn.readfile(sidecar), saved))
betwixt.virtualize(nil, true)
vim.cmd("BetwixtEdit")
-- Delete every block; an empty review must survive reopen.
for _ = 1, 2 do
  local content = lines()
  local start, finish
  for i, line in ipairs(content) do
    if line:find("╭─ betwixt", 1, true) then
      start = i
    end
    if start and line == "-- ╰─ betwixt" then
      finish = i
      break
    end
  end
  vim.api.nvim_buf_set_lines(0, start - 1, finish, false, {})
end
local reject_write = vim.api.nvim_create_autocmd("BufWritePre", {
  buffer = 0,
  callback = function()
    error("reject test write")
  end,
})
assert(not pcall(vim.cmd, "write"))
assert(vim.deep_equal(vim.fn.readfile(sidecar), saved))
vim.api.nvim_del_autocmd(reject_write)
vim.cmd.write()
assert(not table.concat(vim.fn.readfile(sidecar), "\n"):find("## Comment", 1, true))
betwixt.detach(nil, false)
vim.cmd("BetwixtAttach")
betwixt.detach(nil, false)
vim.cmd("BetwixtReload")
assert(vim.fn.exists(":BetwixtEdit") == 2)
betwixt.detach(nil, false)
vim.cmd("BetwixtRefresh")
assert(vim.fn.exists(":BetwixtEdit") == 2)
betwixt.detach(nil, false)
vim.fn.delete(temporary, "rf")
print("betwixt trial workflow: ok")
