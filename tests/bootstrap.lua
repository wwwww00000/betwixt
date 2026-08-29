vim.cmd("runtime plugin/betwixt.lua")
local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
vim.g.mapleader = " "
betwixt.setup({ author = "reviewer" })
vim.cmd("filetype plugin on")

local source_path = vim.fs.joinpath(temporary, "sample.py")
local sidecar_path = source_path .. ".betwixt.md"
local source = {
  "def total(value):",
  "    subtotal = value",
  "    return subtotal",
}
assert(vim.fn.writefile(source, source_path) == 0)
vim.cmd.edit(vim.fn.fnameescape(source_path))
local source_buffer = vim.api.nvim_get_current_buf()

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

local function sidecar_text()
  return table.concat(vim.fn.readfile(sidecar_path), "\n")
end

assert(vim.fn.exists(":BetwixtComment") == 2, "the initial comment command should be globally available")
assert(vim.fn.exists(":BetwixtEdit") == 0, "an untouched buffer should have no attachment commands")
assert(vim.uv.fs_stat(sidecar_path) == nil, "opening a source file must not create a sidecar")

vim.cmd("2,3BetwixtComment risk")
assert(vim.uv.fs_stat(sidecar_path) == nil, "the first sidecar should remain pending until :write")
assert(
  find_line("# ╭─ betwixt · reviewer · open · risk · sample.py:2-3") > 0,
  "the first command should attach and materialize"
)
betwixt.virtualize(source_buffer, true)
assert(vim.uv.fs_stat(sidecar_path) == nil, "discarding the first pending comment should leave no sidecar")
assert(vim.deep_equal(buffer_lines(), source), "discarding the first comment should restore pure source")

vim.cmd("2,3BetwixtComment risk")
local first_body = find_line("# ")
vim.api.nvim_buf_set_lines(source_buffer, first_body - 1, first_body, false, { "# Check the total calculation." })
vim.cmd("write")

assert(vim.uv.fs_stat(sidecar_path) ~= nil, "writing the first comment should create the default sidecar")
assert(vim.deep_equal(vim.fn.readfile(source_path), source), "lazy sidecar creation must not alter source")
local written = sidecar_text()
assert(written:find("file: sample%.py") ~= nil, "the default sidecar should target its adjacent source")
assert(written:find("range: 2%-3") ~= nil, "the first selected range should persist")
assert(
  written:find(
    "anchor:\n        subtotal = value\n        return subtotal\ncontext%-before:\n    def total%(value%):\ncontext%-after:\nbody:"
  ) ~= nil,
  "a first comment should retain adjacent context and the end-of-file boundary"
)
assert(written:find("Check the total calculation%.") ~= nil, "the first comment body should persist")

betwixt.virtualize(source_buffer, false)
betwixt.detach(source_buffer, false)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("BetwixtComment question")
local second_body = find_line("# ")
vim.api.nvim_buf_set_lines(source_buffer, second_body - 1, second_body, false, { "# Is this input always numeric?" })
vim.cmd("write")
written = sidecar_text()
local comment_count = 0
for _ in written:gmatch("## Comment") do
  comment_count = comment_count + 1
end
assert(comment_count == 2, "the initial command should discover and reuse an existing default sidecar")
assert(written:find("Is this input always numeric%?") ~= nil, "the discovered sidecar should accept another comment")

betwixt.virtualize(source_buffer, false)
betwixt.detach(source_buffer, false)
vim.fn.delete(temporary, "rf")
print("betwixt lazy first comment: ok")
